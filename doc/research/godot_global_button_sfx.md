# Godot 4.7 全局按钮点击音效 API 核对

## 结论

项目在 `project.godot` 中声明 Godot 4.7。对全局 UI 点击音效，推荐由常驻 Autoload：

1. 在自身进入场景树后连接 `get_tree().node_added`；
2. 每当节点进入树时，若节点是 `BaseButton`，把它的 `pressed` 信号连接到统一播放方法；
3. 初始化时递归扫描一次场景树，覆盖监听建立前已经存在的按钮；
4. 每次连接前使用 `button.pressed.is_connected(callable)` 去重；
5. 用非定位的 `AudioStreamPlayer` 播放 UI 音效，并显式设置目标音频总线。

这是基于官方 API 行为得出的项目实现建议，不是 Godot 官方提供的专用“全局按钮音效”模式。

## 官方 API 依据与实现注意事项

### 动态节点覆盖

`SceneTree.node_added(node)` 会在节点进入该场景树时发出，因此可覆盖运行时动态创建并随后加入树的按钮。只监听这个信号无法回溯监听建立前已在树中的节点，故初始化时仍应扫描现有树；这是由该信号的触发时机推导出的防漏措施。

来源：[SceneTree.node_added（Godot 4.7）](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html#class-scenetree-signal-node-added)

### 只在有效激活时播放

应监听 `BaseButton.pressed`，而不是原始鼠标输入或 `button_down`。官方说明 `pressed` 在按钮被切换或按下（即激活）时发出；具体发生在按下还是释放阶段由 `action_mode` 决定。这样也自然覆盖键盘、手柄和快捷键触发的按钮激活。

`disabled == true` 时按钮不能被点击或切换，因此用户操作不会形成有效的 `pressed` 激活。按钮在按住期间被禁用时，官方只特别说明会发出 `button_up`；全局音效若监听 `pressed`，不会把该清理事件误当成点击。代码无需在 `pressed` 回调里再次检查 `disabled`，但保留防御性检查也无害。

来源：[BaseButton 信号与 `pressed`](https://docs.godotengine.org/en/4.7/classes/class_basebutton.html#class-basebutton-signal-pressed)、[BaseButton.disabled](https://docs.godotengine.org/en/4.7/classes/class_basebutton.html#class-basebutton-property-disabled)

### 避免重复连接

官方推荐在 GDScript 中直接使用 `button.pressed.connect(callable)`。同一信号不能重复连接到同一 `Callable`；重复连接会返回 `ERR_INVALID_PARAMETER` 并产生错误（除非使用引用计数连接标志）。因此扫描现有节点与监听 `node_added` 并用时，应先调用 `button.pressed.is_connected(callable)`。

若回调需要知道具体按钮，可使用 `Callable.bind(button)`；生成用于检查和连接的 `Callable` 必须一致，避免去重检查失效。

来源：[Signal.connect / Signal.is_connected](https://docs.godotengine.org/en/4.7/classes/class_signal.html#class-signal-method-connect)

### 播放器与总线

`AudioStreamPlayer` 是非定位播放节点，官方明确说明适合 UI 和菜单。其 `bus` 属性决定该播放器所有声音进入的目标总线；若运行时不存在指定总线，Godot 会回退到 `Master`。因此服务应设置项目实际存在的 SFX/UI 总线；若项目当前只有 `Master`，可先显式使用 `Master`，后续建立独立总线时再迁移。

若允许快速连续点击叠音，应评估 `max_polyphony`。官方说明默认值为 `1`，达到上限后再次 `play()` 会切断最早的声音；短促 click 音效通常可按产品体验选择保留单声部或提高并发数。

来源：[AudioStreamPlayer 描述、`bus` 与 `max_polyphony`](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html)

## 空白区域点击与按钮去重

### 为什么使用 `_input()` 覆盖空白区域

Godot 4.7 的输入流程先把事件发送给覆写了 `Node._input()` 的节点，之后才尝试把事件交给 GUI `Control._gui_input()`；`_unhandled_input()` 则只会收到此前未被 `_input()` 或 GUI 消费的事件。因此，全局点击音若既要覆盖空白区域，又要覆盖会被按钮等 GUI 控件消费的指针事件，应在常驻服务的 `_input(event)` 中监听，而不能只依赖 `_unhandled_input()`。

`_input()` 收到的是每个输入事件，而非“有效按钮激活”语义。服务应只筛选目标指针的按下沿，并且不要调用 `Viewport.set_input_as_handled()`，否则会阻止同一事件继续进入 GUI、破坏按钮操作。该选择会让禁用按钮、纯装饰控件和完全空白处的左键/触屏按下都播放点击音，符合“空点击也响”的产品语义。

来源：[Using InputEvent：Godot 4.7 输入传播顺序](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)、[Node._input（Godot 4.7）](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-private-method-input)

### 鼠标左键与触屏按下的判定

`InputEventMouseButton` 表示鼠标按钮的按下或释放；`button_index` 标识具体按钮，`pressed == true` 表示按下，`false` 表示释放。因此桌面端应使用 `event is InputEventMouseButton`、`event.button_index == MOUSE_BUTTON_LEFT` 与 `event.pressed` 的组合，只在左键按下时播放一次，不在释放时再次播放。

`InputEventScreenTouch` 表示触屏按下/释放，`pressed` 同样区分按下与释放；`index` 表示多点触控中的手指编号。若产品定义为“每根手指的一次按下都是一次点击”，应按 `index` 分别维护活动触点，而不能用单个全局布尔量屏蔽所有后续触点。

来源：[InputEventMouseButton（Godot 4.7）](https://docs.godotengine.org/en/4.7/classes/class_inputeventmousebutton.html)、[InputEventScreenTouch（Godot 4.7）](https://docs.godotengine.org/en/4.7/classes/class_inputeventscreentouch.html)、[Input examples：鼠标与触屏事件](https://docs.godotengine.org/en/4.7/tutorials/inputs/input_examples.html)

### 触屏模拟鼠标的重复事件

Godot 可通过 `input_devices/pointing/emulate_mouse_from_touch` 在触屏操作时额外发送鼠标事件，该设置默认开启；反向的 `emulate_touch_from_mouse` 也可能在鼠标操作时额外发送触屏事件。官方为这类模拟事件定义了 `InputEvent.DEVICE_ID_EMULATION`，可用它区分模拟事件与物理设备事件。

因此去重应优先依据事件来源：同一应用同时监听 `InputEventScreenTouch` 和 `InputEventMouseButton` 时，忽略 `device == InputEvent.DEVICE_ID_EMULATION` 的模拟副本，保留物理事件。若项目或目标平台实际产生事件的方式不同，需在真机记录事件类型、`device`、`index` 后再调整；仅用“已有任意指针按下”的全局布尔量虽然能挡住模拟副本，却也会误吞合法的第二根手指。

来源：[InputEvent.DEVICE_ID_EMULATION（Godot 4.7）](https://docs.godotengine.org/en/4.7/classes/class_inputevent.html#class-inputevent-constant-device-id-emulation)、[ProjectSettings 指针模拟设置（Godot 4.7）](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-input-devices-pointing-emulate-mouse-from-touch)

### 与 `BaseButton.pressed` 的去重策略

保留 `BaseButton.pressed` 监听仍有必要，因为键盘、手柄、快捷键或代码触发的按钮激活没有对应的鼠标/触屏按下事件，也应播放点击音。指针点击按钮则会同时经历全局 `_input()` 和按钮 `pressed`，若两个入口都直接播放就会叠音。

官方输入顺序保证 `_input()` 先于 GUI；`BaseButton.pressed` 的发出时机则由 `action_mode` 决定，可以在按下或释放时发生。由此可采用一次性“指针激活额度”：

1. `_input()` 收到真实鼠标左键或触屏按下时立即播放，并登记该指针序列；
2. 若随后按钮发出 `pressed`，消费对应序列但不再播放；
3. 若指针释放且没有按钮消费，在本轮 GUI 分发结束后清理该序列；
4. 没有可消费指针序列的 `pressed` 视为键盘、手柄或代码激活，正常播放。

第 3 步应延迟清理，因为 `_input()` 先看到释放事件，默认在释放阶段激活的按钮随后才进入 GUI 并发出 `pressed`。这是依据官方传播顺序与 `action_mode` 语义推导的项目级去重方案，并非 Godot 提供了指针事件与 `pressed` 信号之间的官方关联 ID。若要严谨支持多点触控、同一帧多事件、按住鼠标时的键盘激活，需将状态按触点/设备维护并做真机事件序列测试；单个布尔量存在误吞独立激活的风险。

来源：[Using InputEvent：Godot 4.7 输入传播顺序](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)、[BaseButton.pressed 与 `action_mode`](https://docs.godotengine.org/en/4.7/classes/class_basebutton.html#class-basebutton-signal-pressed)

## 推荐伪代码

```gdscript
func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    _scan_existing_buttons(get_tree().root)

func _register_button(button: BaseButton) -> void:
    var callback := _play_click
    if not button.pressed.is_connected(callback):
        button.pressed.connect(callback)
```

实际项目代码应按项目规范补充中文模块职责与边界说明；如果需对特定按钮静音，可再定义组或元数据作为显式排除机制。

## 版本与未验证项

- `project.godot` 声明 `config/features=PackedStringArray("4.7", "GL Compatibility")`；本文固定引用 Godot 4.7 官方类参考，避免 `latest` 文档随开发版本漂移。
- 本研究未运行 Godot 4.7 编辑器，未实测 Autoload 初始化顺序、场景切换、动态按钮、快捷键触发和暂停树状态；这些应在接入后按项目 Godot 验收规范验证。
- 官方文档确认禁用按钮不可点击/切换，但没有在同一条目中逐字写明“禁用按钮绝不发出 `pressed`”；本文结论来自 `disabled` 与 `pressed` 定义的合并判断。建议接入测试显式覆盖这一边界。
