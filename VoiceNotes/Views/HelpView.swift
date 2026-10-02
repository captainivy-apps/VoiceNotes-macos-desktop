import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("语音记事是什么", [
                "语音记事是一款本地优先的语音记录工具。你说话，应用会先保存录音，再通过 ASR 生成识别稿，并可用 LLM 整理成更通顺的润色稿。"
            ])
            section("功能特点", [
                "• 录音、识别稿、润色稿三段式流程",
                "• 记事列表按时间管理，可多选删除",
                "• 详情页支持试听、编辑、复制、下载与上一篇/下一篇切换",
                "• ASR 模型可下载到本地后离线识别",
                "• 可配置 OpenAI 兼容接口进行文本润色"
            ])
            section("快速上手", [
                "1. 在“录制”页开始录音或上传音频文件。",
                "2. 录音保存后点击“开始语音识别”。",
                "3. 可直接保存为润色稿，或先用 LLM 加工后保存。",
                "4. 到“记事”页查看历史记录，点击可进入详情编辑和导出。"
            ])
            section("设置建议", [
                "• 首次使用先下载一个 ASR 模型并设为当前模型。",
                "• 可添加多组 LLM 配置并设默认；录制与详情页可临时切换。",
                "• 填写 Base URL / API Key / Model Name 后先测试连接再保存。"
            ])
            section("常见问题", [
                "• 识别失败：请检查模型是否下载完成，或重试录音文件。",
                "• LLM 连接失败：确认 Base URL、API Key 和网络/代理设置。",
                "• 找不到文件：导出内容默认保存在系统“下载”目录。"
            ])
            Text("如果你只想快速记录：录音 → 识别 → 直接保存为润色稿 就可以完成一次记事。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            ForEach(lines, id: \.self) { line in
                Text(line).font(.body)
            }
        }
    }
}
