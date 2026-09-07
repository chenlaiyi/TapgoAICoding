import TapgoCore

func runComposerLocalCommandTests(_ t: TestRunner) {
    t.expectEqual(ComposerLocalCommand.parse("/goal 核对界面"), .goal("核对界面"), "goal command stays local")
    t.expectEqual(ComposerLocalCommand.parse(" /goal\n多行目标 \n"), .goal("多行目标"), "goal trims only command whitespace")
    t.expectEqual(ComposerLocalCommand.parse("/goal"), .goal(""), "empty goal opens local editor instead of reaching model")
    t.expectEqual(ComposerLocalCommand.parse("/new"), .newTask, "new task command stays local")
    t.expectNil(ComposerLocalCommand.parse("/goalkeeper"), "command name boundary preserves ordinary prompts")
    t.expectNil(ComposerLocalCommand.parse("请解释 /goal"), "inline command mention is regular text")
    // /clear — only the bare token is a local command; any suffix falls back to model.
    t.expectEqual(ComposerLocalCommand.parse("/clear"), .clear, "clear command stays local")
    t.expectEqual(ComposerLocalCommand.parse("  /clear  "), .clear, "clear trims surrounding whitespace")
    t.expectNil(ComposerLocalCommand.parse("/clear conversation"), "clear with suffix is not a local command")
    t.expectNil(ComposerLocalCommand.parse("/clearance"), "clear-prefixed names are not intercepted")
    t.expectNil(ComposerLocalCommand.parse("/clearAll"), "clear-with-suffix is not intercepted")
    // /model — bare token has no query and is rejected so users don't accidentally
    // open the model picker; only `/model <query>` is a local command.
    t.expectNil(ComposerLocalCommand.parse("/model"), "bare /model stays ordinary text")
    t.expectEqual(ComposerLocalCommand.parse("/model MiniMax M3"), .model("MiniMax M3"), "model with display-name query is local")
    t.expectEqual(ComposerLocalCommand.parse("  /model   glm-flash  "), .model("glm-flash"), "model trims surrounding whitespace")
    t.expectEqual(ComposerLocalCommand.parse("/model builtin:minimax::MiniMax-M3"), .model("builtin:minimax::MiniMax-M3"), "model accepts exact provider::model id")
    t.expectNil(ComposerLocalCommand.parse("/modelA"), "model-prefixed names are not intercepted")
    t.expectNil(ComposerLocalCommand.parse("/modeling"), "model-with-suffix is not intercepted")
    t.expectNil(ComposerLocalCommand.parse("请解释 /model"), "inline /model mention is regular text")
    // /init — bare token opens a draft-AGENTS.md thread; suffix falls back to model.
    t.expectEqual(ComposerLocalCommand.parse("/init"), .initProject, "bare /init opens the init thread")
    t.expectEqual(ComposerLocalCommand.parse("  /init  "), .initProject, "/init trims surrounding whitespace")
    t.expectNil(ComposerLocalCommand.parse("/init AGENTS"), "/init with suffix is not a local command")
    t.expectNil(ComposerLocalCommand.parse("/initial"), "init-prefixed names are not intercepted")
    t.expectNil(ComposerLocalCommand.parse("/initialize"), "init-with-suffix is not intercepted")
    t.expectNil(ComposerLocalCommand.parse("请解释 /init"), "inline /init mention is regular text")
}
