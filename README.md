# ここいった

写真から旅行の記録と都道府県の訪問状態を管理する Flutter Android アプリです。

## 開発コマンド

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## データ保護

- アプリ状態はバージョン付き JSON で保存します。
- 写真は1つの旅行、または「旅行未設定」のどちらか一方に所属します。
- 完全復元は ZIP の形式・件数・容量・SHA-256を検証して一時領域へ展開します。
- 復元確定前に現在データの安全バックアップを作成し、保存状態の切替に失敗した場合は新しい写真セットをロールバックします。

## Androidリリース署名

GitHub Actions のリリースには次の Secrets が必要です。

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

タグ `v*.*.*` の push、または手動実行で署名済み APK を作成します。署名情報が不足している場合、ワークフローはリリース前に失敗します。
