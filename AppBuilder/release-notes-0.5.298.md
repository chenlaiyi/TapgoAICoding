# v0.5.298

fix(evolution): state schema 版本漂移

## 变更

- 修正 evolve.sh write_state 写出的 schemaVersion：EVO-041 把注册表升到 v4（新增 costSource）但漏改写入方，导致新记录仍标 v3；validate 把 v3 当 legacy 放过，正是 EVO-035 要消灭的静默漂移。
- evolution-schema 回归新增漂移守卫：从注册表读 evolution_state.json 的版本、从 evolve.sh write_state 段读写入字面量，两者必须相等；负向验证（写回 3）确认守卫会失败。
- 本机现有 state 已带 costSource 字段，本轮发布起落盘 schemaVersion=4。

写入方版本号对齐注册表并加守卫

## Next

EVO-042 反馈漏斗接入看板: 把 drafts/转化率/等待时长显示到 App 指标详情与手机端自进化卡片
