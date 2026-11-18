import { describe, it, expect } from '@ohos/hypium';
import { RemoteEntry, SyncFileFilter, SyncPathGuard, SyncSafetyReason } from '@ohos/domain';
import { SyncBaseline } from '@ohos/vault';
import { SyncDecision, SyncEngine } from '@ohos/sync';

function makeEntry(path: string, etag: string, serverTag: string = ''): RemoteEntry {
  const entry: RemoteEntry = new RemoteEntry();
  entry.path = path;
  entry.etag = etag;
  entry.serverTag = serverTag;
  return entry;
}

function makeBaseline(fileHash: string, serverTag: string = '', mtime: number = 1000,
  size: number = 128, lastSyncAt: number = 1010000, state: string = 'synced',
  targetKey: string = 'https://dav.example.com/dav|vault'): SyncBaseline {
  const baseline: SyncBaseline = new SyncBaseline();
  baseline.fileHash = fileHash;
  baseline.serverTag = serverTag;
  baseline.mtime = mtime;
  baseline.size = size;
  baseline.lastSyncAt = lastSyncAt;
  baseline.state = state;
  baseline.targetKey = targetKey;
  return baseline;
}

export default function syncEngineTest() {
  describe('SyncEngineDecisionTest', () => {
    it('pushes new local file when remote is absent', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-a');
      expect(SyncEngine.decideLocalEntry(local, undefined, undefined)).assertEqual(SyncDecision.PUSH_NEW);
    });

    it('skips when local and remote etag match and serverTag is unchanged', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-a');
      const remote: RemoteEntry = makeEntry('note.md', 'hash-a', 'etag-1');
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      expect(SyncEngine.decideLocalEntry(local, remote, baseline)).assertEqual(SyncDecision.NONE);
    });

    it('pulls external change when manifest hash matches but serverTag changed', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-a');
      const remote: RemoteEntry = makeEntry('note.md', 'hash-a', 'etag-2');
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      expect(SyncEngine.decideLocalEntry(local, remote, baseline)).assertEqual(SyncDecision.PULL_EXTERNAL);
    });

    it('pushes local change when remote still matches baseline', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-b');
      const remote: RemoteEntry = makeEntry('note.md', 'hash-a', 'etag-1');
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      expect(SyncEngine.decideLocalEntry(local, remote, baseline)).assertEqual(SyncDecision.PUSH_CHANGED);
    });

    it('pulls remote change when local still matches baseline', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-a');
      const remote: RemoteEntry = makeEntry('note.md', 'hash-c', 'etag-2');
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      expect(SyncEngine.decideLocalEntry(local, remote, baseline)).assertEqual(SyncDecision.PULL_CHANGED);
    });

    it('flags conflict when both local and remote diverged from baseline', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-b');
      const remote: RemoteEntry = makeEntry('note.md', 'hash-c', 'etag-2');
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      expect(SyncEngine.decideLocalEntry(local, remote, baseline)).assertEqual(SyncDecision.CONFLICT);
    });

    it('handles unhashed remote entries via serverTag or content check', 0, () => {
      const local: RemoteEntry = makeEntry('note.md', 'hash-a');
      const remoteSameTag: RemoteEntry = makeEntry('note.md', '', 'etag-1');
      const remoteNewTag: RemoteEntry = makeEntry('note.md', '', 'etag-2');
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      expect(SyncEngine.decideLocalEntry(local, remoteSameTag, baseline, true)).assertEqual(SyncDecision.NONE);
      expect(SyncEngine.decideLocalEntry(local, remoteNewTag, baseline, true)).assertEqual(SyncDecision.CHECK_CONTENT);
      expect(SyncEngine.decideLocalEntry(local, remoteNewTag, baseline, false)).assertEqual(SyncDecision.CONFLICT);
    });

    it('propagates remote deletion to local trash only with synced unchanged baseline', 0, () => {
      const key: string = 'https://dav.example.com/dav|vault';
      const local: RemoteEntry = makeEntry('note.md', 'hash-a');
      const syncedBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1');
      const locallyModifiedBaseline: SyncBaseline = makeBaseline('hash-b', 'etag-1');
      const conflictBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1',
        1000, 128, 1010000, 'conflict');
      const tombstoneBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1',
        1000, 128, 1010000, 'local_deleted');
      const legacyBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1',
        1000, 128, 1010000, 'synced', '');
      const otherTargetBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1',
        1000, 128, 1010000, 'synced', 'https://other/dav|vault');
      // 远端消失 + 本地仍是上次同步原样 + 基线属于当前同步目标：传播删除到本地回收站
      expect(SyncEngine.decideLocalEntry(local, undefined, syncedBaseline, true, key))
        .assertEqual(SyncDecision.TRASH_LOCAL);
      // 基线 targetKey 为空（历史遗留）或属于其他同步目标：不能证明当前远端删过它，
      // 绝不误删本地，保守重新推送
      expect(SyncEngine.decideLocalEntry(local, undefined, legacyBaseline, true, key))
        .assertEqual(SyncDecision.PUSH_NEW);
      expect(SyncEngine.decideLocalEntry(local, undefined, otherTargetBaseline, true, key))
        .assertEqual(SyncDecision.PUSH_NEW);
      // 调用方未提供当前目标（targetKey 为空）：同样不触发删除
      expect(SyncEngine.decideLocalEntry(local, undefined, syncedBaseline, true, ''))
        .assertEqual(SyncDecision.PUSH_NEW);
      // 远端消失但本地已改 / 基线非 synced：保留本地并重新推送
      expect(SyncEngine.decideLocalEntry(local, undefined, locallyModifiedBaseline, true, key))
        .assertEqual(SyncDecision.PUSH_NEW);
      expect(SyncEngine.decideLocalEntry(local, undefined, conflictBaseline, true, key))
        .assertEqual(SyncDecision.PUSH_NEW);
      expect(SyncEngine.decideLocalEntry(local, undefined, tombstoneBaseline, true, key))
        .assertEqual(SyncDecision.PUSH_NEW);
      // 无基线（新增文件）：照常推送
      expect(SyncEngine.decideLocalEntry(local, undefined, undefined, true, key))
        .assertEqual(SyncDecision.PUSH_NEW);
    });

    it('soft-trashes remote only when targetKey matches synced baseline, never otherwise', 0, () => {
      const key: string = 'https://dav.example.com/dav|vault';
      const remote: RemoteEntry = makeEntry('note.md', 'hash-a', 'etag-1');
      const matchedBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1', 1000, 128, 1010000, 'synced', key);
      const otherTargetBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1', 1000, 128, 1010000, 'synced', 'https://other/dav|vault');
      const legacyBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1', 1000, 128, 1010000, 'synced', '');
      expect(SyncEngine.decideRemoteOnly(remote, undefined, key)).assertEqual(SyncDecision.PULL_NEW);
      expect(SyncEngine.decideRemoteOnly(remote, matchedBaseline, key)).assertEqual(SyncDecision.TRASH_REMOTE);
      expect(SyncEngine.decideRemoteOnly(remote, otherTargetBaseline, key)).assertEqual(SyncDecision.PULL_NEW);
      expect(SyncEngine.decideRemoteOnly(remote, legacyBaseline, key)).assertEqual(SyncDecision.PULL_NEW);
    });

    it('respects local_deleted tombstone until remote file changes externally', 0, () => {
      const key: string = 'https://dav.example.com/dav|vault';
      const tombstone: SyncBaseline = makeBaseline('hash-a', 'etag-1', 1000, 128, 1010000, 'local_deleted', key);
      const remoteUnchanged: RemoteEntry = makeEntry('note.md', 'hash-a', 'etag-1');
      const remoteTagChanged: RemoteEntry = makeEntry('note.md', '', 'etag-2');
      const remoteHashChanged: RemoteEntry = makeEntry('note.md', 'hash-b', 'etag-2');
      expect(SyncEngine.decideRemoteOnly(remoteUnchanged, tombstone, key))
        .assertEqual(SyncDecision.SKIP_DELETED_LOCAL);
      expect(SyncEngine.decideRemoteOnly(remoteTagChanged, tombstone, key))
        .assertEqual(SyncDecision.PULL_NEW);
      expect(SyncEngine.decideRemoteOnly(remoteHashChanged, tombstone, key))
        .assertEqual(SyncDecision.PULL_NEW);
    });

    it('evaluates safety gates for target switch, initial non-empty merge, and bulk trash', 0, () => {
      // 存在实际变更时：切换目标与首次互推/冲突仍触发保护
      expect(SyncEngine.evaluateSafetyGate(2, 3, 0, 0, 0, true, 5, 2))
        .assertEqual(SyncSafetyReason.TARGET_CHANGED);
      expect(SyncEngine.evaluateSafetyGate(3, 5, 0, 0, 0, false, 4, 2))
        .assertEqual(SyncSafetyReason.INITIAL_NON_EMPTY_MERGE);
      // 两端零差异或仅纯拉取（零写入远端/零冲突）时无感放行
      expect(SyncEngine.evaluateSafetyGate(3, 5, 0, 0, 0, false, 0, 0))
        .assertEqual(SyncSafetyReason.NONE);
      expect(SyncEngine.evaluateSafetyGate(3, 5, 0, 0, 0, true, 0, 0))
        .assertEqual(SyncSafetyReason.NONE);
      expect(SyncEngine.evaluateSafetyGate(3, 5, 0, 0, 0, false, 2, 0))
        .assertEqual(SyncSafetyReason.NONE);
      expect(SyncEngine.evaluateSafetyGate(0, 5, 0, 0, 0, false))
        .assertEqual(SyncSafetyReason.NONE);
      // 批量移入 .trash/ 阈值（>=10 个或基线 >=10 时占比 >=30%）
      expect(SyncEngine.evaluateSafetyGate(10, 20, 20, 10, 20, false, 10, 10))
        .assertEqual(SyncSafetyReason.BULK_TRASH);
      expect(SyncEngine.evaluateSafetyGate(7, 10, 10, 3, 10, false, 3, 3))
        .assertEqual(SyncSafetyReason.BULK_TRASH);
      expect(SyncEngine.evaluateSafetyGate(18, 20, 20, 2, 20, false, 2, 2))
        .assertEqual(SyncSafetyReason.NONE);
    });

    it('normalizes target key and detects baseline target mismatch', 0, () => {
      expect(SyncEngine.buildTargetKey(' https://DAV.Example.COM/dav/// ', ' /Obsidian/Vault/ '))
        .assertEqual('https://dav.example.com/dav|Obsidian/Vault');
      const map: Map<string, SyncBaseline> = new Map<string, SyncBaseline>();
      map.set('a.md', makeBaseline('h1', 't1', 1000, 10, 1010000, 'synced', 'https://dav.a/dav|v1'));
      expect(SyncEngine.isBaselineTargetCompatible(map, 'https://dav.a/dav|v1')).assertTrue();
      expect(SyncEngine.isBaselineTargetCompatible(map, 'https://dav.a/dav|v2')).assertFalse();
    });

    it('builds valid remote .trash paths and protects Obsidian internal paths', 0, () => {
      const trashPath: string = SyncEngine.buildRemoteTrashPath('folder/note.md', '20261115210000', 2);
      expect(trashPath).assertEqual('.trash/20261115210000_2_note.md');
      expect(SyncPathGuard.isValidTrashPath(trashPath)).assertTrue();
      expect(SyncPathGuard.isValidTrashPath('.trash/../evil.md')).assertFalse();
      expect(SyncPathGuard.isValidTrashPath('.obsidian/config.json')).assertFalse();

      expect(SyncPathGuard.isSafeSyncPath('folder/note.md')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('assets/photo.png')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('.obsidian/plugins/dataview/README.md')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('.obsidian/app.json')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('.trash/deleted.md')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('.mysidian/manifest.json')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('.git/HEAD')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('conflicts/2026_note.md')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('docs/board.canvas')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('docs/paper.pdf')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('attachments/report.docx')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('attachments/sheet.xlsx')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('attachments/deck.pptx')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('attachments/sketch.excalidraw')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('attachments/audio.mp3')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('attachments/video.mp4')).assertTrue();
      expect(SyncPathGuard.isSafeSyncPath('backup.zip')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('draft.tmp')).assertFalse();
      expect(SyncPathGuard.isSafeSyncPath('vault.db')).assertFalse();
      expect(SyncFileFilter.isSyncable('attachment/spec.pdf')).assertTrue();
      expect(SyncFileFilter.isBinary('attachment/spec.pdf')).assertTrue();
      expect(SyncFileFilter.isImage('attachment/spec.pdf')).assertFalse();
      expect(SyncFileFilter.isImage('attachments/pic.png')).assertTrue();
      expect(SyncFileFilter.isSyncable('docs/report.docx')).assertTrue();
      expect(SyncFileFilter.isSyncable('backup.zip')).assertFalse();
    });

    it('parses and matches .mysidianignore rules cleanly', 0, () => {
      const rules: string[] = SyncPathGuard.parseIgnoreRules(
        '# comment\nTemplates/\n*.excalidraw\n/Inbox/scratch.md\n');
      expect(rules.length).assertEqual(3);
      expect(SyncPathGuard.isIgnoredByRules('Templates/daily.md', rules)).assertTrue();
      expect(SyncPathGuard.isIgnoredByRules('sketch.excalidraw', rules)).assertTrue();
      expect(SyncPathGuard.isIgnoredByRules('Inbox/scratch.md', rules)).assertTrue();
      expect(SyncPathGuard.isIgnoredByRules('Notes/daily.md', rules)).assertFalse();
    });

    it('reuses baseline sha256 only when mtime and size match and file is older than 2s before sync', 0, () => {
      const baseline: SyncBaseline = makeBaseline('hash-a', 'etag-1', 1000, 256, 1005000);
      expect(SyncEngine.isHashReusable(baseline, 1000, 256)).assertTrue();
      expect(SyncEngine.isHashReusable(baseline, 1001, 256)).assertFalse();
      expect(SyncEngine.isHashReusable(baseline, 1000, 512)).assertFalse();
      const racedBaseline: SyncBaseline = makeBaseline('hash-a', 'etag-1', 1000, 256, 1001000);
      expect(SyncEngine.isHashReusable(racedBaseline, 1000, 256)).assertFalse();
    });
  });
}
