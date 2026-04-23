# YamiboReader Swift

`YamiboReader Swift` 是一个面向百合会内容的小说/漫画阅读器的 Swift / SwiftUI 实现。


## 当前能力

### 论坛浏览

- 基于 `WebKit` 提供百合会移动版论坛浏览入口
- 支持从论坛页面进入小说或漫画阅读流程
- 提供“论坛 / 收藏 / 我的”三标签主界面

### 收藏与同步

- 支持拉取并展示百合会收藏页内容
- 支持本地收藏库、分组、排序、筛选与手动整理
- 支持同步远端收藏并合并到本地状态

### 小说阅读

- 提供阅读内容抓取、HTML 解析与正文清洗能力
- 支持章节标题归一化、章节切换和阅读进度保存
- 提供分页与纵向两种阅读模式相关的布局与状态支持
- 包含阅读缓存、分页计算和阅读器设置相关基础设施

### 漫画阅读

- 支持漫画目录、章节、页面与图片地址相关解析
- 提供原生漫画阅读器，支持分页 / 纵向阅读切换
- 包含章节跳转、阅读进度保存、图片缓存与网页回退流程
- 在无法顺利进入原生阅读时，可回退到网页漫画视图

### 登录态与本地能力

- 支持会话状态、Cookie / UA 等访问上下文的持久化管理
- 提供百合会每日签到能力，并包含快捷指令入口
- 支持阅读缓存、漫画图片缓存、目录缓存与设置存储
- 提供应用数据重置与本地 Web 数据清理能力

## 运行与验证

### Swift Package

仓库通过 [`Package.swift`](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/Package.swift) 定义核心模块，当前声明支持：

- `iOS 17+`

依赖：

- [`SwiftSoup`](https://github.com/scinfu/SwiftSoup)

在仓库根目录执行测试：

```bash
swift test
```

### iOS App

iOS App 入口位于 [YamiboReaderIOS/YamiboReaderIOSApp.swift](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/YamiboReaderIOS/YamiboReaderIOSApp.swift)，对应的 Xcode 工程位于 [YamiboReaderIOS.xcodeproj](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/YamiboReaderIOS.xcodeproj)。

如果需要在模拟器或真机中运行，直接使用该工程打开并构建即可。

## 项目结构

- [Sources/YamiboReaderCore](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/Sources/YamiboReaderCore)
  负责数据模型、网络访问、HTML 解析、阅读 / 漫画支持逻辑、缓存与本地存储。
- [Sources/YamiboReaderUI](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/Sources/YamiboReaderUI)
  负责 SwiftUI 界面、论坛容器、收藏页、小说阅读器与漫画阅读器的交互层。
- [YamiboReaderIOS](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/YamiboReaderIOS)
  提供独立的 iOS App 入口、资源和系统集成能力。
- [Tests](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/Tests)
  包含核心解析、阅读流程、漫画流程、路由与界面状态相关测试。

## TODO

- 更完善的 iPad 支持
- 章节评论查看
- 更新检查
- 更新订阅

## 特别感谢

- [prprbell/YamiboReaderPro](https://github.com/prprbell/YamiboReaderPro)
- [flben233/YamiboReader](https://github.com/flben233/YamiboReader)
- [scinfu/SwiftSoup](https://github.com/scinfu/SwiftSoup)

## 为什么要做本项目？

~~因为我自己要看~~

## License

本项目采用 `GNU Affero General Public License v3.0` (`AGPL-3.0`) 许可发布。详见 [LICENSE](/Users/arkalin/Documents/MyDocuments/YamiboReader/YamiboReaderSwift/LICENSE)。
