#!/usr/bin/env python3
"""Real Helper actions against the disposable AppKit fixture; never edits user apps.
Requires the fixture and existing TCC grants. Optional cursor probe prints JSON
with cursor coordinates and overlay windows (see validation instructions).
"""
import json, os, re, select, subprocess, sys, time
APP = '/tmp/Tapgo CU Fixture.app'
helper = sys.argv[1]
probe = sys.argv[2] if len(sys.argv) > 2 else None
process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
seq = 0
checks = 0

def check(ok, label):
    global checks
    if not ok: raise AssertionError(label)
    checks += 1
    print('PASS:', label, flush=True)

def pointer():
    return json.loads(subprocess.check_output([probe], text=True))

def call(name, **args):
    global seq
    seq += 1
    before = pointer()['cursor'] if probe and name in ('click','drag') else None
    process.stdin.write(json.dumps(dict(jsonrpc='2.0', id=seq, method='tools/call', params=dict(name=name, arguments=dict(app=APP, **args))))+'\n')
    process.stdin.flush()
    seen = []
    deadline = time.monotonic()+20
    while not select.select([process.stdout], [], [], .025)[0]:
        if time.monotonic()>deadline: raise TimeoutError(name)
        if probe and name in ('click','type_text','drag'):
            seen += pointer()['overlays']
    response = json.loads(process.stdout.readline())
    result = response['result']
    check(not result.get('isError'), name + ' accepted: ' + str(result.get('content'))[:250] if result.get('isError') else name+' accepted')
    if probe and name in ('click','type_text','drag'):
        check(bool(seen), name+' rendered independent agent pointer')
        check(all(w['layer'] == 25 for w in seen), name+' overlay above normal windows')
    if before is not None:
        print('POINTER:', name, before, pointer()['cursor'], flush=True)
    return '\n'.join(x.get('text','') for x in result.get('content',[]))

def observe():
    return call('get_ax_state', disableDiffing=True)

def index(state, needle):
    return int(next(re.match(r'^(\d+)',line).group(1) for line in state.splitlines() if needle in line))

try:
    # The fixture can take a moment to complete its first activation.
    deadline = time.monotonic() + 5
    state = observe()
    while 'id="fixture-input"' not in state and time.monotonic() < deadline:
        time.sleep(.1)
        state = observe()
    time.sleep(.2)
    state = observe()
    initial = pointer()['cursor'] if probe else None
    call('click', element_index=index(state, 'id="fixture-input"'))
    call('press_key', key='super+a')
    call('type_text', text='Tapgo 独立光标 123')
    state = observe()
    check('value="Tapgo 独立光标 123"' in state, 'real keyboard input exact readback')
    check('value="leave this field unchanged"' in state, 'click moved focus away from the other field')
    call('click', element_index=index(state, 'title="Apply fixture"'))
    state = observe()
    check('Applied: Tapgo 独立光标 123' in state, 'semantic button effect readback')
    call('set_value', element_index=index(state, 'id="fixture-input"'), value='coordinate click')
    # Point coordinates relative to the fixture window, including title bar.
    call('click', x=104, y=216)
    state = observe()
    check('Applied: coordinate click' in state, 'coordinate click changed button result')
    # Select text with actual mouse drag, then replace via keyboard.
    call('click', x=180, y=97)
    call('press_key', key='super+a')
    call('type_text', text='drag text')
    call('drag', from_x=30, from_y=97, to_x=180, to_y=97)
    call('type_text', text='replaced')
    state = observe()
    check('value="replaced"' in state, 'mouse drag selected text and keyboard replaced selection')
    if probe:
        final = pointer()
        check(not final['overlays'], 'one-shot cursor cleaned up')
        check(initial == final['cursor'], 'hardware pointer unchanged across app actions')
    print(f'{checks} checks passed', flush=True)
finally:
    process.stdin.close()
    process.wait(timeout=20)
