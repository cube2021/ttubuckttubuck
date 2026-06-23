import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  List<String> _lines = [];

  @override
  void initState() {
    super.initState();
    _lines = LogService.instance.getAll();
    LogService.instance.stream.listen((list) {
      setState(() => _lines = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reversed = _lines.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('앱 로그 뷰어'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '전체 복사',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: LogService.instance.exportText()));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그가 클립보드에 복사되었습니다.')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: '지우기',
            onPressed: () {
              LogService.instance.clear();
            },
          ),
        ],
      ),
      body: reversed.isEmpty
          ? const Center(child: Text('로그가 없습니다.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: reversed.length,
              itemBuilder: (context, i) {
                final line = reversed[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(line, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                );
              },
            ),
    );
  }
}
