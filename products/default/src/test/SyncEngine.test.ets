import { describe, it, expect } from '@ohos/hypium';
import { RemoteEntry } from '@ohos/domain';
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
  size: number = 128, lastSyncAt: number = 1010000): SyncBaseline {
  const baseline: SyncBaseline = new SyncBaseline();
  baseline.fileHash = fileHash;
  baseline.serverTag = serverTag;
  baseline.mtime = mtime;
  baseline.size = size;
  baseline.lastSyncAt = lastSyncAt;
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

    it('decides remote-only entry as delete when in baseline or pull when new', 0, () => {
      expect(SyncEngine.decideRemoteOnlyEntry(true)).assertEqual(SyncDecision.DELETE_REMOTE);
      expect(SyncEngine.decideRemoteOnlyEntry(false)).assertEqual(SyncDecision.PULL_NEW);
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
