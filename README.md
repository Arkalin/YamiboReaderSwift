# YamiboReader Swift Port

这是给现有 Android 工程并行推进的 Swift 迁移目录，当前目标不是一次性取代原项目，而是先把最稳定的业务层和主界面骨架迁出来。

## 当前内容

- `Sources/YamiboReaderCore`
  - 收藏、章节、阅读内容等 Swift 数据模型
  - 百合会常用路由封装
  - `URLSession` 网络客户端
  - 收藏页与漫画列表的基础 HTML 解析
  - 标题清洗与章节号提取
- `Sources/YamiboReaderUI`
  - SwiftUI 的主标签页骨架
  - `WebKit` 论坛浏览容器
  - 收藏页 ViewModel 与列表展示
- `Tests/YamiboReaderCoreTests`
  - 解析器与标题清洗的基础测试

## 运行与验证

在本目录执行：

```bash
swift test
```

## 迁移进度

已完成：

- 论坛浏览入口的 SwiftUI/WebKit 原型
- 收藏同步与基础页面解析
- 漫画标题清洗、TID 提取、章节号提取

待继续：

- 原生小说阅读器
- 原生漫画阅读器与图片探测逻辑
- Cookie 持久化与登录态同步
- 真正的 iOS app target / Xcode 工程封装
