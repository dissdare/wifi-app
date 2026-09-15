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
    r'''echo; systemctl stop app; resp=$(ec20 'AT+QCFG="usbnet"' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'+QCFG: "usbnet",1'* ]]; then echo "已激活"; elif [[ $resp == *'+QCFG: "usbnet",'* ]]; then echo "未激活"; else echo "未知响应"; fi; systemctl start app; echo''',
  ),
  CommandDef(
    '激活ec20',
    r'''echo; systemctl stop app; resp=$(ec20 'AT+QCFG="usbnet",1' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'recv msg:OK'* ]]; then echo "激活成功"; elif [[ $resp == *'ERROR'* ]]; then echo "激活失败"; else echo "未知响应"; fi; systemctl start app; echo''',
  ),
  CommandDef(
    '查看插卡状态',
    r'''echo; systemctl stop app; resp=$(ec20 'AT+CPIN?' 2>&1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'READY'* ]]; then echo "识卡成功"; elif [[ $resp == *'ERROR'* ]]; then echo "识卡失败"; else echo "未知响应"; fi; systemctl start app; echo''',
  ),
  CommandDef(
    '查看信号质量',
    r'''echo; systemctl stop app; resp=$(ec20 'AT+CSQ' 2>&1); csq=$(printf '%s\n' "$resp" | grep -oP '\+CSQ:\s*\K[0-9]+' | head -n1); if [[ $resp == *"The serial ports did not open correctly"* ]]; then echo "和ec20通信失败"; elif [[ $resp == *'+CSQ: 99'* ]]; then echo "信号有问题，请排查sim卡问题"; elif [ -n "$csq" ]; then echo "信号质量：$csq"; else echo "未知响应"; fi; systemctl start app; echo''',
  ),
  CommandDef(
    '联网检测',
    r'''echo; ((ping -c5 -W2 -i1 www.baidu.com >/dev/null 2>&1 && echo OK) & (ping -c5 -W2 -i1 8.8.8.8 >/dev/null 2>&1 && echo OK) & wait ) | grep -q OK && echo "联网成功" || echo "联网失败"; echo''',
  ),
  CommandDef('中断当前操作', '', interrupt: true),
];
