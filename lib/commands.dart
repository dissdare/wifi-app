/// 预设指令定义。
class CommandDef {
  /// 按钮上显示的名称。
  final String label;

  /// 发送到终端 shell 的命令文本（不含结尾换行）。
  final String command;

  /// 是否为「中断当前操作」：发送 Ctrl+C，忽略 [command]。
  final bool interrupt;

  const CommandDef(this.label, this.command, {this.interrupt = false});
}

/// 预设指令列表。
const List<CommandDef> presetCommands = [
  CommandDef(
    '查看ec20激活状态',
    r'''resp=$(ec20 'AT+QCFG="usbnet"' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'+QCFG: "usbnet",1'* ]]; then echo "已激活"; elif [[ $resp == *'+QCFG: "usbnet",'* ]]; then echo "未激活"; else echo "未知响应"; fi''',
  ),
  CommandDef(
    '激活ec20',
    r'''resp=$(ec20 'AT+QCFG="usbnet",1' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'recv msg:OK'* ]]; then echo "激活成功"; elif [[ $resp == *'ERROR'* ]]; then echo "激活失败"; else echo "未知响应"; fi''',
  ),
  CommandDef('中断当前操作', '', interrupt: true),
];
