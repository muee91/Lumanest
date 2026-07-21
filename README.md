# LumaNest

栖光——循光而行，择光而栖。

An environment-aware photography companion for landscape, outdoor, and
humanity-focused exploration.

## Current milestone

- Android-first Flutter foundation with iOS-compatible structure.
- Context snapshots drive a no-placeholder UI manifest.
- Five persistent destinations: Today, Explore, Route, Inspiration, Profile.
- Low-motion ambient canvas with accessibility controls.

## Verify

```bash
flutter analyze
flutter test
./tool/flutter_with_environment.sh test
./tool/flutter_with_environment.sh build apk --debug
```

`test` 始终使用无真实 Broker 配置的隔离环境。只有需要验证真实服务的集成测试才使用
`./tool/flutter_with_environment.sh test-configured <测试路径>`；真机运行继续使用
`./tool/flutter_with_environment.sh run`。
