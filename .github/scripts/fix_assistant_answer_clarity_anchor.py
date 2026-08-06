from pathlib import Path

path = Path('.github/scripts/apply_assistant_answer_clarity.py')
text = path.read_text(encoding='utf-8')
marker = "\nserver = 'services/lumanest-data-broker/src/server.mjs'\n"
if marker not in text:
    raise SystemExit('assistant clarity server marker not found')
prefix = text.split(marker, 1)[0]
material_import = "import 'package:flutter/material.dart';\n"
if prefix.count(material_import) < 1:
    raise SystemExit('assistant summary material import not found')
prefix = prefix.replace(material_import, '', 1)
old_points = r'''          if (summary.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 11),
            const _SectionLabel(label: '重点'),
            const SizedBox(height: 5),
            for (final point in summary.keyPoints)
              _PointRow(
                key: const Key('assistant-decision-key-point'),
                text: point,
              ),
          ],
'''
new_points = r'''          if (summary.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 11),
            const _SectionLabel(label: '重点'),
            const SizedBox(height: 5),
            Column(
              key: const Key('assistant-decision-key-points'),
              children: [
                for (final point in summary.keyPoints) _PointRow(text: point),
              ],
            ),
          ],
'''
if prefix.count(old_points) != 1:
    raise SystemExit('assistant summary key point source block not found')
prefix = prefix.replace(old_points, new_points, 1)
old_test_key = "Key('assistant-decision-key-point')"
if prefix.count(old_test_key) != 2:
    raise SystemExit(
        f'expected two assistant key point test keys, found {prefix.count(old_test_key)}'
    )
prefix = prefix.replace(old_test_key, "Key('assistant-decision-key-points')")
replacement = r'''
server = 'services/lumanest-data-broker/src/server.mjs'
server_path = Path(server)
server_text = server_path.read_text(encoding='utf-8')

import re

general_pattern = (
    r'用中文单段回答，不超过200字。只输出 JSON：'
    r'\{\\?"answer\\?":\\?"回答\\?"\}。'
)
general_replacement = (
    '用中文回答，不超过180字。首行必须是“结论｜...”且只给一句直接判断；'
    '随后最多3行“依据｜...”；必要时最多2行“限制｜...”；最后可给1行“下一步｜...”。'
    '不要寒暄、复述问题、使用 Markdown 标题或连续长段落。'
    '只输出 JSON：{"answer":"按上述行格式组成的回答"}。'
)
server_text, count = re.subn(general_pattern, general_replacement, server_text, count=1)
if count != 1:
    raise SystemExit(f'{server}: general assistant prompt tail not found')

contextual_pattern = (
    r'只输出 JSON：\{\\?"answer\\?":\\?"不超过160字\\?"\}。'
)
contextual_replacement = (
    '回答不超过160字。首行必须是“结论｜...”且保留 templateAnswer 的直接判断；'
    '随后最多3行“依据｜...”；必要时最多2行“限制｜...”；最后可给1行“下一步｜...”。'
    '不要寒暄、复述问题、使用 Markdown 标题或连续长段落。'
    '只输出 JSON：{"answer":"按上述行格式组成的回答"}。'
)
server_text, count = re.subn(
    contextual_pattern,
    contextual_replacement,
    server_text,
    count=1,
)
if count != 1:
    raise SystemExit(f'{server}: contextual assistant prompt tail not found')
server_path.write_text(server_text, encoding='utf-8')
'''
path.write_text(prefix + marker + replacement.lstrip('\n'), encoding='utf-8')
