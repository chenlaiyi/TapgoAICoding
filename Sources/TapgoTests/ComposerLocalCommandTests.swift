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
}
