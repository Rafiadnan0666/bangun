import re

path = 'lib/screens/home_screen.dart'
with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    c = f.read()

# Remove every occurrence of the broken dropdown block (multi-line)
pattern = re.compile(
    r'\n\s*DropdownButton<ModelChoice>\(.*?\),\n',
    re.DOTALL,
)
c = pattern.sub('\n', c)

# Add import if missing
if "import '../data/coco_detector.dart';" not in c:
    c = c.replace(
        "import '../data/alarm_repository.dart';",
        "import '../data/alarm_repository.dart';\nimport '../data/coco_detector.dart';",
    )

# Insert one dropdown after the subtitle row (before SizedBox height 2 or after wake smart text)
marker = "                'wake smart · stop by scan or math',"
if marker in c:
    dropdown = (
        "                Row(\n"
        "                  children: [\n"
        "                    const Text('Model:', style: TextStyle(fontSize: 11, color: Bg.sub)),\n"
        "                    const SizedBox(width: 8),\n"
        "                    DropdownButton<ModelChoice>(\n"
        "                      value: CocoDetector.selected,\n"
        "                      underline: const SizedBox.shrink(),\n"
        "                      style: const TextStyle(fontSize: 12, color: Bg.ink),\n"
        "                      items: ModelChoice.values.map((m) => DropdownMenuItem(\n"
        "                        value: m,\n"
        "                        child: Text(m == ModelChoice.ssdMobileNet ? 'SSD MobileNet' : 'YOLO11n 90'),\n"
        "                      )).toList(),\n"
        "                      onChanged: (m) {\n"
        "                        if (m != null) setState(() => CocoDetector.selected = m);\n"
        "                      },\n"
        "                    ),\n"
        "                  ],\n"
        "                ),\n"
    )
    # insert after the Text block ending with style line + closing paren
    close = "                style: TextStyle(fontSize: 12, color: Bg.sub, height: 1.2),\n              ),\n"
    if close in c:
        c = c.replace(close, close + dropdown, 1)
    else:
        print('close marker missing')
else:
    print('wake marker missing')

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
print('cleaned and inserted dropdown once')
