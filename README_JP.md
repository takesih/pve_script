# Proxmox VE 管理スクリプトコレクション
Proxmox VE 環境で使用できる様々な管理スクリプトのコレクションです。

<div align="center">
  <h3>🌍 言語選択</h3>
  <a href="README.md">🇰🇷 한국어</a> |
  <a href="README_EN.md">🇺🇸 English</a> |
  <a href="README_CN.md">🇨🇳 中文</a> |
  <a href="README_JP.md">🇯🇵 日本語</a> |
  <a href="README_ES.md">🇪🇸 Español</a> |
  <a href="README_FR.md">🇫🇷 Français</a> |
  <a href="README_DE.md">🇩🇪 Deutsch</a> |
  <a href="README_RU.md">🇷🇺 Русский</a> |
  <a href="README_PT.md">🇵🇹 Português</a> |
  <a href="README_AR.md">🇸🇦 العربية</a>
</div>

---

## スクリプト一覧

### 1. VMブリッジDHCP設定ツール
vmbr0ブリッジをDHCPモードに変換またはバックアップから復元するスクリプトです。

**機能：**
- **DHCP変換**：vmbr0を静的IPからDHCPモードに変換
- **バックアップ復元**：以前の設定をバックアップから復元
- **自動バックアップ**：変更前に現在の設定を自動バックアップ

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. LVMリサイズツール
local-lvmをlocalに統合してディスク容量を最適化するスクリプトです。

**⚠️ 重要：このスクリプトを使用すると元に戻すことが困難で、スナップショットバックアップが機能しません。**

**機能：**
- **LVM統合**：local-lvmをlocalに統合
- **自動リサイズ**：rootボリュームを自動拡張
- **安全検証**：作業前にシステム状態を確認

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. DNSZI DDNS自動更新ツール
DNSZIサービスのためのDDNS自動更新を設定するスクリプトです。

**機能：**
- **自動インストール**：cronサービスの自動インストールと設定
- **起動時更新**：システム起動時に自動DDNS更新
- **定期更新**：3時間ごとに自動DDNS更新
- **簡単削除**：設定完全削除機能

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

### 4. Supabase LXC自動インストールツール ⚠️ **テスト段階**

> **⚠️ 警告：このスクリプトは現在テスト段階です。本番環境では使用しないでください！**
> 
> テスト目的でのみ使用してください。データ損失やシステム問題が発生する可能性があります。

Proxmox VEのLXCコンテナにSupabase開発環境を自動インストールするスクリプトです。

**インストールされるサービス：**
- **Docker & Docker Compose**：コンテナランタイム環境
- **Dockge**（ポート5001）：Docker Composeスタック Web管理ツール
- **CloudCmd**（ポート8000）：Webベースファイルマネージャー
- **Supabase**（ポート3001, 8001）：オープンソースFirebase代替

**主な機能：**
- **完全自動化**：対話式設定でワンクリックインストール
- **最新バージョン**：すべてのコンポーネントの最新バージョンを自動インストール
- **セキュリティ強化**：ファイアウォール、fail2ban、ファイル権限の自動設定
- **統合テスト**：インストール後の自動検証とステータス確認
- **詳細ログ**：完全なインストールプロセスログとトラブルシューティングガイド

**システム要件：**
- Proxmox VE 7.0以上
- 最小8GB RAM（推奨）
- 最小50GBディスク容量（推奨）
- インターネット接続必須

**実行方法：**
```bash
# ⚠️ テスト環境でのみ使用してください！
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**インストール後のアクセス：**
- Dockge管理パネル：`http://コンテナIP:5001`
- CloudCmdファイル管理：`http://コンテナIP:8000`
- Supabase Studio：`http://コンテナIP:3001`
- Supabase API：`http://コンテナIP:8001`

### 5. Proxmox ISOカスタマイズツール
Proxmox 8.4 ISOにRealtek R8168ネットワークカードドライバーを統合するスクリプトです。

**機能：**
- **ISOダウンロード**：公式Proxmox 8.4 ISOの自動ダウンロード
- **ドライバー統合**：Realtek R8168ドライバーをinitrdに統合
- **ブートメニュー**：カスタムブートメニュー作成
- **パッケージング**：新しいISOファイル生成

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```



---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 