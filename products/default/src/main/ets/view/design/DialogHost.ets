import { PromptAction } from '@kit.ArkUI';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { noteTitleFromPath } from './NoteActionHelper';

/** 对话框场景类型。 */
export class DesignDialogKind {
  static readonly NONE: string = '';
  static readonly CREATE_VAULT: string = 'create_vault';
  static readonly RENAME: string = 'rename';
  static readonly NEW_FOLDER: string = 'new_folder';
  static readonly MOVE: string = 'move';
}

/** 新建仓库请求：名称 + 可选 WebDAV 同步配置（由 @Entry 落库并触发首次同步）。 */
export class CreateVaultRequest {
  name: string;
  withSync: boolean;
  serverUrl: string;
  username: string;
  password: string;
  remoteRoot: string;
  skipCertVerify: boolean;

  constructor(name: string, withSync: boolean, serverUrl: string, username: string,
    password: string, remoteRoot: string, skipCertVerify: boolean = false) {
    this.name = name;
    this.withSync = withSync;
    this.serverUrl = serverUrl;
    this.username = username;
    this.password = password;
    this.remoteRoot = remoteRoot;
    this.skipCertVerify = skipCertVerify;
  }
}

/**
 * Material 3 对话框基座（scrim + 卡片 + 场景插槽）。
 *
 * 场景：新建仓库（含 WebDAV 4 字段开关）/ 重命名 / 新建文件夹 / 移动目录选择。
 * 组件按需挂载（父级 if 条件渲染），每次打开均为全新实例，内部状态在
 * aboutToAppear 按场景预填。重命名 / 文件夹 / 移动直接操作 vm；
 * 新建仓库经 onCreateVault 上抛 @Entry（涉及 syncVm 与自动同步定时器）。
 */
@ComponentV2
export struct DialogHost {
  @Param kind: string = DesignDialogKind.RENAME;
  /** 指定要重命名/移动的笔记路径；为空时回退到当前已选笔记 vm.selectedPath。 */
  @Param targetPath: string = '';
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};
  @Event onCreateVault: (request: CreateVaultRequest) => void =
    (_request: CreateVaultRequest): void => {};

  /** 输入框文本（重命名 / 新建文件夹 / 新建仓库名共用）。 */
  @Local inputText: string = '';
  /** 新建仓库：是否同时配置 WebDAV 同步。 */
  @Local createWithSync: boolean = true;
  /** 新建仓库：WebDAV 四字段。 */
  @Local syncUrl: string = '';
  @Local syncUser: string = '';
  @Local syncPass: string = '';
  @Local syncRoot: string = '';
  /** 新建仓库：是否跳过 WebDAV HTTPS 证书校验。 */
  @Local skipCertVerify: boolean = false;
  /** 移动场景：目标目录列表。 */
  @Local moveDirs: string[] = [];

  aboutToAppear(): void {
    if (this.kind === DesignDialogKind.RENAME) {
      const target: string = this.effectiveTargetPath();
      this.inputText = target.length > 0 ? noteTitleFromPath(target) : '';
      return;
    }
    if (this.kind === DesignDialogKind.NEW_FOLDER) {
      this.inputText = this.vm.pendingFolderPrefix;
      this.vm.pendingFolderPrefix = '';
      return;
    }
    if (this.kind === DesignDialogKind.CREATE_VAULT) {
      this.inputText = this.vm.vaults.length === 0 ? '示例仓库' : '';
      this.createWithSync = true;
      this.skipCertVerify = false;
      return;
    }
    if (this.kind === DesignDialogKind.MOVE) {
      this.moveDirs = this.vm.listDirs();
    }
  }

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_dim'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction }))
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Text(this.dialogTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .width('100%')
          .margin({ bottom: 12 })

        if (this.kind === DesignDialogKind.CREATE_VAULT) {
          this.createVaultContent()
        } else if (this.kind === DesignDialogKind.MOVE) {
          this.moveContent()
        } else {
          this.inputContent()
        }

        Row() {
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(16)
            .backgroundColor($r('app.color.design_elevated'))
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .margin({ right: 12 })
            .onClick(() => {
              this.onClose();
            })
          if (this.kind !== DesignDialogKind.MOVE) {
            Button(this.kind === DesignDialogKind.RENAME ?
              $r('app.string.dialog_confirm') : $r('app.string.dialog_create'))
              .type(ButtonType.Capsule)
              .height(40)
              .fontSize(16)
              .backgroundColor($r('app.color.design_accent'))
              .fontColor($r('app.color.design_on_accent'))
              .layoutWeight(1)
              .onClick(() => {
                this.confirm();
              })
          }
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 460, maxHeight: '84%' })
      .padding(24)
      .borderRadius(28)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 场景内容 ====================

  /** 重命名 / 新建文件夹：单输入框。 */
  @Builder
  inputContent() {
    TextInput({
      placeholder: this.kind === DesignDialogKind.RENAME ?
        $r('app.string.dialog_rename_hint') : $r('app.string.dialog_folder_hint'),
      text: this.inputText
    })
      .width('100%')
      .height(44)
      .fontSize(15)
      .padding({ left: 14, right: 14 })
      .borderRadius(12)
      .backgroundColor($r('app.color.design_elevated'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .placeholderColor($r('app.color.design_text_secondary'))
      .fontColor($r('app.color.design_text_primary'))
      .caretColor($r('app.color.design_accent'))
      .onChange((value: string) => {
        this.inputText = value;
      })
  }

  /** 新建仓库：命名 + WebDAV 同步开关与四字段。 */
  @Builder
  createVaultContent() {
    Scroll() {
      Column() {
        TextInput({
          placeholder: $r('app.string.dialog_vault_name'),
          text: this.inputText
        })
          .width('100%')
          .height(44)
          .fontSize(16)
          .padding({ left: 14, right: 14 })
          .borderRadius(12)
          .backgroundColor($r('app.color.design_elevated'))
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .placeholderColor($r('app.color.design_text_secondary'))
          .fontColor($r('app.color.design_text_primary'))
          .caretColor($r('app.color.design_accent'))
          .onChange((value: string) => {
            this.inputText = value;
          })
          .margin({ bottom: 12 })

        Row() {
          Column() {
            Text($r('app.string.dialog_create_with_sync'))
              .fontSize(14)
              .fontColor($r('app.color.design_text_primary'))
            Text($r('app.string.dialog_create_with_sync_desc'))
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.createWithSync })
            .selectedColor($r('app.color.design_accent'))
            .onChange((isOn: boolean) => {
              this.createWithSync = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 4 })

        if (this.createWithSync) {
          this.fieldLabel($r('app.string.sync_server'))
          this.fieldInput($r('app.string.sync_server_placeholder'), InputType.Normal,
            (value: string): void => {
              this.syncUrl = value;
            })
          this.fieldLabel($r('app.string.sync_username'))
          this.fieldInput($r('app.string.sync_username_placeholder'), InputType.Normal,
            (value: string): void => {
              this.syncUser = value;
            })
          this.fieldLabel($r('app.string.sync_password'))
          this.fieldInput($r('app.string.sync_password_placeholder'), InputType.Password,
            (value: string): void => {
              this.syncPass = value;
            })
          this.fieldLabel($r('app.string.sync_root'))
          this.fieldInput($r('app.string.sync_root_placeholder'), InputType.Normal,
            (value: string): void => {
              this.syncRoot = value;
            })
          Row() {
            Column() {
              Text($r('app.string.sync_skip_cert'))
                .fontSize(14)
                .fontColor($r('app.color.design_text_primary'))
              Text(this.skipCertVerify ? $r('app.string.sync_skip_cert_warning') :
                $r('app.string.sync_skip_cert_desc'))
                .fontSize(12)
                .fontColor(this.skipCertVerify ? $r('app.color.design_danger') :
                  $r('app.color.design_text_secondary'))
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.skipCertVerify })
              .selectedColor($r('app.color.design_danger'))
              .onChange((isOn: boolean) => {
                this.skipCertVerify = isOn;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 10, bottom: 2 })
          Text($r('app.string.dialog_create_with_sync_safe_hint'))
            .fontSize(11)
            .fontColor($r('app.color.design_text_secondary'))
            .lineHeight(16)
            .width('100%')
            .margin({ top: 8 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: 320 })
  }

  /** 新建仓库：字段标签。 */
  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.design_text_secondary'))
      .width('100%')
      .margin({ top: 8, bottom: 6 })
  }

  /** 新建仓库：字段输入框。 */
  @Builder
  fieldInput(placeholder: ResourceStr, inputType: InputType, onChange: (value: string) => void) {
    TextInput({
      placeholder: placeholder
    })
      .type(inputType)
      .width('100%')
      .height(42)
      .fontSize(15)
      .padding({ left: 12, right: 12 })
      .borderRadius(10)
      .backgroundColor($r('app.color.design_elevated'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .placeholderColor($r('app.color.design_text_secondary'))
      .fontColor($r('app.color.design_text_primary'))
      .caretColor($r('app.color.design_accent'))
      .onChange((value: string) => {
        onChange(value);
      })
  }

  /** 移动场景：目标目录列表（根目录 + 各目录）。 */
  @Builder
  moveContent() {
    Scroll() {
      Column() {
        this.moveTargetRow($r('app.string.dialog_move_root'), '')
        ForEach(this.moveDirs, (dir: string, index: number) => {
          this.moveTargetRow(dir, dir)
        }, (dir: string, index: number): string => `move_${index}_${dir}`)
      }
      .width('100%')
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: 280 })
  }

  /** 移动场景：目标目录条目。 */
  @Builder
  moveTargetRow(label: ResourceStr, dir: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(16)
        .fontColor([$r('app.color.design_text_secondary')])
        .width(20)
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.design_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 6, right: 6 })
    .borderRadius(10)
    .onClick(() => {
      this.confirmMoveTo(dir);
    })
  }

  // ==================== 确认逻辑 ====================

  /** 对话框标题。 */
  private dialogTitle(): ResourceStr {
    if (this.kind === DesignDialogKind.CREATE_VAULT) {
      return $r('app.string.action_create_vault');
    }
    if (this.kind === DesignDialogKind.RENAME) {
      return $r('app.string.dialog_rename_title');
    }
    if (this.kind === DesignDialogKind.NEW_FOLDER) {
      return $r('app.string.dialog_folder_title');
    }
    return $r('app.string.dialog_move_title');
  }

  /** 确认：按场景分发。 */
  private confirm(): void {
    if (this.kind === DesignDialogKind.CREATE_VAULT) {
      this.confirmCreateVault();
      return;
    }
    if (this.kind === DesignDialogKind.RENAME) {
      this.confirmRename();
      return;
    }
    if (this.kind === DesignDialogKind.NEW_FOLDER) {
      this.confirmCreateFolder();
    }
  }

  /** 确认新建仓库：上抛 @Entry 落库（含 WebDAV 配置与首次同步）。 */
  private confirmCreateVault(): void {
    const name: string = this.inputText.trim();
    this.onClose();
    if (name.length === 0) {
      return;
    }
    this.onCreateVault(new CreateVaultRequest(name, this.createWithSync,
      this.syncUrl.trim(), this.syncUser.trim(), this.syncPass, this.syncRoot.trim(),
      this.skipCertVerify));
  }

  private effectiveTargetPath(): string {
    return this.targetPath.length > 0 ? this.targetPath : this.vm.selectedPath;
  }

  /** 确认重命名：重命名会同步重写指向旧名的双链。 */
  private confirmRename(): void {
    const target: string = this.inputText.trim();
    const path: string = this.effectiveTargetPath();
    // E3：onClose 后本组件可能已卸载，异步回调里的 toast 必须用关闭前捕获的 PromptAction。
    const prompt: PromptAction = this.getUIContext().getPromptAction();
    this.onClose();
    if (target.length === 0 || path.length === 0) {
      return;
    }
    this.vm.renameNote(path, target).then((ok: boolean): void => {
      if (!ok) {
        prompt.showToast({ message: $r('app.string.msg_rename_failed') });
        return;
      }
      prompt.showToast({ message: $r('app.string.msg_rename_done') });
      this.onNoteMutated();
    });
  }

  /** 确认新建文件夹。 */
  private confirmCreateFolder(): void {
    const name: string = this.inputText.trim();
    // E3：同 confirmRename，关闭后异步 toast 用关闭前捕获的 PromptAction。
    const prompt: PromptAction = this.getUIContext().getPromptAction();
    this.onClose();
    if (name.length === 0) {
      return;
    }
    this.vm.createFolder(name).then((ok: boolean): void => {
      if (!ok) {
        prompt.showToast({ message: $r('app.string.msg_folder_failed') });
        return;
      }
      prompt.showToast({ message: $r('app.string.msg_folder_done') });
    });
  }

  /** 确认移动到目标目录。 */
  private confirmMoveTo(dir: string): void {
    const path: string = this.effectiveTargetPath();
    // E3：同 confirmRename，关闭后异步 toast 用关闭前捕获的 PromptAction。
    const prompt: PromptAction = this.getUIContext().getPromptAction();
    this.onClose();
    if (path.length === 0) {
      return;
    }
    this.vm.moveNote(path, dir).then((ok: boolean): void => {
      if (!ok) {
        prompt.showToast({ message: $r('app.string.msg_move_failed') });
        return;
      }
      prompt.showToast({ message: $r('app.string.msg_move_done') });
      this.onNoteMutated();
    });
  }
}
