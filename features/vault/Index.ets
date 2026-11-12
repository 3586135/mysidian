export { DbHelper } from './src/main/ets/db/DbHelper';
export { VaultDao } from './src/main/ets/db/VaultDao';
export { NoteDao } from './src/main/ets/db/NoteDao';
export { BlockDao } from './src/main/ets/db/BlockDao';
export { LinkDao } from './src/main/ets/db/LinkDao';
export { TagDao } from './src/main/ets/db/TagDao';
export { PropDao } from './src/main/ets/db/PropDao';
export { SearchDao } from './src/main/ets/db/SearchDao';
export { SyncStateDao, SyncBaseline, SyncBaselineRow } from './src/main/ets/db/SyncStateDao';

export { VaultManager, FileStatInfo } from './src/main/ets/manager/VaultManager';
export { VaultPath } from './src/main/ets/manager/VaultPath';
export { ZipTransfer } from './src/main/ets/manager/ZipTransfer';
export { NoteResolver } from './src/main/ets/manager/NoteResolver';
export { LinkRewriter } from './src/main/ets/manager/LinkRewriter';
export { AttachmentResolver } from './src/main/ets/manager/AttachmentResolver';
export { TemplateEngine, TemplateRenderResult } from './src/main/ets/manager/TemplateEngine';
export { FileHistory, HistorySnapshot, DiffLine } from './src/main/ets/manager/FileHistory';
export { FuzzyMatcher } from './src/main/ets/manager/FuzzyMatcher';

export { IndexPipeline } from './src/main/ets/indexer/IndexPipeline';
export { Tokenizer } from './src/main/ets/indexer/Tokenizer';
