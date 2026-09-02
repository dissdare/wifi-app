/// 预设指令定义。
class CommandDef {
  /// 按钮上显示的名称。
  final String label;

  /// 发送到终端 shell 的命令文本（不含结尾换行）。
  final String command;

  const CommandDef(this.label, this.command);
}

/// WiFi 直连下的预设指令列表（ec20 相关操作）。
///
/// 命令开头和结尾各加一个 `echo`，让返回结果前后各空一行，更醒目。
const List<CommandDef> presetCommands = [
  CommandDef(
    '查看ec20激活状态',
    r'''echo; resp=$(ec20 'AT+QCFG="usbnet"' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'+QCFG: "usbnet",1'* ]]; then echo "已激活"; elif [[ $resp == *'+QCFG: "usbnet",'* ]]; then echo "未激活"; else echo "未知响应"; fi; echo''',
  ),
  CommandDef(
    '激活ec20',
    r'''echo; resp=$(ec20 'AT+QCFG="usbnet",1' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'recv msg:OK'* ]]; then echo "激活成功"; elif [[ $resp == *'ERROR'* ]]; then echo "激活失败"; else echo "未知响应"; fi; echo''',
  ),
];

/// 远程连接（frp）下无预设指令（中断操作已由底部 Ctrl+C 组合键承担）。
const List<CommandDef> remotePresetCommands = [];
