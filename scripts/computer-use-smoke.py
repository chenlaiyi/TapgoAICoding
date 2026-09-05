#!/usr/bin/env python3
"""Exercise a signed Helper against the disposable computer-use-fixture.swift app.

Usage: python3 scripts/computer-use-smoke.py /path/to/TapgoComputerUseMCP
Requires existing Accessibility + Screen Recording grants; never changes TCC.
Only the test fixture is edited. stdout contains synthetic test results only.
"""
import json
import re
import subprocess
import sys

APP = "/tmp/Tapgo CU Fixture.app"
process = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
sequence = 0
passed = 0


def check(condition, label):
    global passed
    if not condition:
        raise AssertionError(label)
    passed += 1
    print("PASS:", label, flush=True)


def call(name, **arguments):
    global sequence
    sequence += 1
    request = dict(jsonrpc="2.0", id=sequence, method="tools/call", params=dict(name=name, arguments=arguments))
    process.stdin.write(json.dumps(request) + "\n")
    process.stdin.flush()
    response = json.loads(process.stdout.readline())
    check(response.get("id") == sequence, "response id " + str(sequence))
    return response["result"]


def text(result):
    return "\n".join(item.get("text", "") for item in result.get("content", []))


def observe():
    result = call("get_ax_state", app=APP, disableDiffing=True)
    check(not result.get("isError"), "AX read")
    check(not any(item["type"] == "image" for item in result["content"]), "AX-only omits image")
    check(bool(result.get("structuredContent", {}).get("observation_token")), "AX has worker token")
    return text(result)


def index(state, marker):
    for line in state.splitlines():
        if marker in line:
            return int(re.match(r"^(\d+)", line).group(1))
    raise AssertionError("missing fixture element " + marker)


try:
    state = observe()
    field = index(state, 'id="fixture-input"')
    result = call("set_value", app=APP, element_index=field, value="校准 alpha alpha")
    check(not result.get("isError"), "set_value accepted across one-shot workers")
    check(call("click", app=APP, element_index=field).get("isError"), "reused index blocked")
    state = observe()
    check('value="校准 alpha alpha"' in state, "input value readback")
    result = call("click", app=APP, element_index=index(state, 'title="Apply fixture"'))
    check(not result.get("isError"), "semantic click")
    state = observe()
    check("Applied: 校准 alpha alpha" in state, "button effect readback")
    result = call("select_text", app=APP, element_index=index(state, 'id="fixture-input"'),
                  text="alpha", prefix="alpha ", selection_type="text")
    check(not result.get("isError"), "disambiguated selection")
    result = call("paste", app=APP, text="beta", format="text")
    check(not result.get("isError"), "paste dispatch")
    state = observe()
    check('value="校准 alpha beta"' in state, "paste exact text readback")
    shot = call("get_screenshot", app=APP)
    check(any(item["type"] == "image" for item in shot["content"]), "real window screenshot")
    check(call("click", app=APP, element_index=field).get("isError"), "screenshot invalidates indices")
    full = call("get_ax_state", app=APP)
    check(text(full).startswith("App: "), "screenshot resets diff baseline")
    combined = call("get_ax_state_and_screenshot", app=APP, disableDiffing=True)
    check(any(item["type"] == "image" for item in combined["content"]), "combined image")
    check(bool(combined.get("structuredContent", {}).get("observation_token")), "combined retains token")
    result = call("click", app=APP, element_index=index(text(combined), 'title="Open small dialog"'))
    check(not result.get("isError"), "combined token actionable")
    shot = call("get_screenshot", app=APP)
    check("280x" in text(shot), "small front dialog selected instead of large main window")
    print(f"{passed} checks passed", flush=True)
finally:
    process.stdin.close()
    process.wait(timeout=20)
