import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 新建技能（v16：从一级页降为 sheet，ROADMAP 2.2）
//
// 四步向导占一个一级页是过度设计：自己做技能是低频动作，且四步里真正需要
// 界面的只有第一步（起名建文件）。其余三步本质是「去会话里干活」的提示。

// MARK: - 原创作页（v15 一级页，WP-D）
//
// 四步线：① 建骨架（SkillScaffold，与 atlas new 同一份 core 逻辑）→ ② 沙箱试跑
//（复用 requestSandbox 确认流程与四条注意事项）→ ③ 触发验证（TriggerLab，
// 目标是草稿排第一）→ ④ 命中回访（写回后收件箱出回访卡；处方双入口之一）。
// 步进状态持久化（StudioStore），中途退出回来接着走。

struct NewSkillSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var studio = StudioStore()

    var body: some View {
        let draft = studio.draftSkill(appStore: store)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                if let error = studio.error {
                    ReceiptLine(text: error, failed: true) { studio.error = nil }
                        .receiptTransition(reduceMotion: reduceMotion)
                }
                StepCard(index: 1, title: L("建骨架"), state: draft == nil ? .active : .done) {
                    if let draft {
                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            Text(LF("已建「%@」。SKILL.md 是脚手架，把触发三元组和步骤交给会话里的 agent 填。", draft.name))
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Theme.Space.s12) {
                                linkButton(L("打开技能详情")) { store.select(draft.name) }
                                linkButton(L("在访达中显示")) { store.openFolder(draft.sourcePath) }
                                Spacer()
                                Button(L("换一个想法")) { studio.reset() }
                                    .buttonStyle(.plain)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                    .help(L("只清这里的步进，不会删除已建的技能"))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            HStack(spacing: Theme.Space.s8) {
                                TextField(L("技能名，小写字母数字连字符，比如 weekly-report"), text: Binding(
                                    get: { studio.draftName },
                                    set: { studio.draftName = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(Theme.Fonts.callout)
                                .padding(.horizontal, Theme.Space.s12)
                                .frame(height: 32)
                                .quietControl()
                                AtlasPrimaryButton(
                                    title: L("建骨架"),
                                    enabled: SkillScaffold.sanitize(studio.draftName).count >= 2
                                ) { studio.create(appStore: store) }
                            }
                            Toggle(isOn: Binding(
                                get: { studio.includeClipboard },
                                set: { studio.includeClipboard = $0 }
                            )) {
                                Text(L("把剪贴板内容放进草稿（适合刚复制了一段流程）"))
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }
                }

                StepCard(index: 2, title: L("沙箱试跑"), state: stepTwoState(draft)) {
                    if let draft {
                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            ForEach(SkillSandbox.plan(for: draft).caveats, id: \.self) { caveat in
                                HStack(alignment: .top, spacing: Theme.Space.s8) {
                                    Text("·")
                                        .font(Theme.Fonts.secondary)
                                        .foregroundStyle(Theme.textTertiary)
                                    Text(caveat)
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            HStack {
                                AtlasPrimaryButton(title: L("开一个只装它的会话…")) {
                                    store.requestSandbox(draft)
                                }
                                .help(L("在隔离环境里只装这一个技能试跑"))
                                if store.sandboxCount > 0 {
                                    Text(LF("当前 %d 个试跑目录，设置页可一键清理", store.sandboxCount))
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    } else {
                        lockedHint(L("先建骨架"))
                    }
                }

                StepCard(index: 3, title: L("触发验证"), state: stepThreeState(draft)) {
                    if let draft {
                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            Text(L("说一句用户会说的话，看它能不能排到第一。排不到就改 description 里的触发词。"))
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textTertiary)
                            HStack(spacing: Theme.Space.s8) {
                                TextField(LF("比如「帮我用 %@ 做…」的场景原话", draft.name), text: Binding(
                                    get: { studio.simulateText },
                                    set: { studio.simulateText = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(Theme.Fonts.callout)
                                .padding(.horizontal, Theme.Space.s12)
                                .frame(height: 32)
                                .quietControl()
                                .onSubmit { studio.runSimulate(appStore: store) }
                                AtlasPrimaryButton(
                                    title: L("预演"),
                                    enabled: studio.simulateText.trimmingCharacters(in: .whitespaces).count >= 2
                                ) { studio.runSimulate(appStore: store) }
                                .help(L("看这句话会不会把它排到第一"))
                            }
                            if !studio.candidates.isEmpty {
                                simulateResults(draft: draft)
                            }
                        }
                    } else {
                        lockedHint(L("先建骨架"))
                    }
                }

                StepCard(index: 4, title: L("命中回访"), state: draft == nil ? .locked : .active) {
                    if let draft {
                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            Text(L("描述改写写回两周后，收件箱会出回访卡，对比前后触发次数。现在也能直接开处方调描述。"))
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Theme.Space.s12) {
                                if draft.origin != .ccSwitch {
                                    linkButton(L("开处方")) { store.requestPrescription(draft) }
                                }
                                linkButton(L("打开收件箱")) { store.nav = .check }
                            }
                        }
                    } else {
                        lockedHint(L("先建骨架"))
                    }
                }
            }
            .padding(Theme.Space.s20)
            .animation(reduceMotion ? nil : Motion.standard, value: studio.error)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .panelScroll()
        .contentSurface()
        .onAppear {
            studio.validateDraft(appStore: store)
            store.refreshSandboxCount()
            if let phrase = store.simulatePhrase {
                store.simulatePhrase = nil
                studio.simulateText = phrase
                studio.runSimulate(appStore: store)
            }
        }
    }

    /// 试跑过（本次会话建了沙箱目录）就算走完这一步
    private func stepTwoState(_ draft: Skill?) -> StudioStepState {
        guard draft != nil else { return .locked }
        return store.sandboxCount > 0 ? .done : .active
    }

    private func stepThreeState(_ draft: Skill?) -> StudioStepState {
        guard draft != nil else { return .locked }
        return studio.rankedFirst ? .done : .active
    }

    @ViewBuilder
    private func simulateResults(draft: Skill) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            ForEach(Array(studio.candidates.prefix(3).enumerated()), id: \.element.id) { index, candidate in
                let isDraft = candidate.skill.directory == draft.directory
                HStack(spacing: Theme.Space.s8) {
                    Text("\(index + 1)")
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(isDraft ? Theme.accent : Theme.textTertiary)
                        .frame(width: 14)
                    Text(candidate.skill.name)
                        .font(isDraft ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                        .foregroundStyle(isDraft ? Theme.accent : Theme.textSecondary)
                    if !candidate.matched.isEmpty {
                        Text(candidate.matched.prefix(3).joined(separator: L("、")))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("\(candidate.score)")
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if studio.rankedFirst {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.healthy)
                    Text(L("这句话能唤到它。真实会话里说同样的话即可。"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 2)
            } else if let first = studio.candidates.first, first.skill.directory != draft.directory {
                Text(LF("现在第一名是「%@」。把你刚才那句话里的关键词写进 %@ 的 description。", first.skill.name, draft.name))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(Theme.Space.s8 + 2)
        .quietControl(cornerRadius: Theme.Radius.control + 2)
    }

    private func lockedHint(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.textTertiary)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(Theme.accent)
    }
}

private enum StudioStepState {
    case locked, active, done
}

/// 四步线的步卡：编号圈 + 标题 + 状态（锁定 / 进行中 / 已完成）
private struct StepCard<Content: View>: View {
    var index: Int
    var title: String
    var state: StudioStepState
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            ZStack {
                Circle()
                    .fill(badgeFill)
                    .frame(width: 22, height: 22)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(state == .active ? .white : Theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(title)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(state == .locked ? Theme.textTertiary : Theme.textPrimary)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.tile)
        .opacity(state == .locked ? 0.75 : 1)
    }

    private var badgeFill: Color {
        switch state {
        case .locked: return Color.primary.opacity(0.08)
        case .active: return Theme.accent
        case .done: return Theme.healthy
        }
    }
}
