with open('lib/screens/home_screen.dart', 'r', encoding='utf-8', errors='ignore') as f:
    c = f.read()
marker = '              const Text('
insert = "              DropdownButton<ModelChoice>(\n                value: CocoDetector.selected,\n                underline: Container(height:1,color:Colors.grey),\n                items: ModelChoice.values.map((m) => DropdownMenuItem(value:m, child: Text(m == ModelChoice.ssdMobileNet ? 'SSD MobileNet' : 'YOLO11n 90'))).toList(),\n                onChanged: (m) { if (m != null) CocoDetector.selected = m; },\n              ),\n"
if 'DropdownButton' not in c:
    c = c.replace(marker, insert + marker)
    with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
        f.write(c)
    print('dropdown inserted')
else:
    print('already present')
