import 'dart:async';
import 'dart:io' show Platform, File, Directory;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:universal_html/html.dart' as html;

void main() {
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouTube Channel Downloader',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: const DownloadPage(),
    );
  }
}

/// 다운로드 페이지의 UI
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final TextEditingController _urlController = TextEditingController(); // URL 입력을 위한 컨트롤러
  final YoutubeExplode _yt = YoutubeExplode(); // 유튜브 데이터를 가져오기 위한 핵심 객체
  bool _isDownloading = false; // 현재 다운로드 중인지 여부
  String _status = kIsWeb
      ? '웹 브라우저 환경입니다. 파일은 브라우저 설정에 따라 다운로드됩니다.'
      : 'URL을 입력하고 다운로드를 시작하세요.';
  double _progress = 0.0; // 다운로드 진행률 (0.0 ~ 1.0)
  String _currentFileName = ''; // 현재 처리 중인 파일 이름
  String _lastSavedPath = ''; // 파일이 저장된 경로

  @override
  void dispose() {
    _yt.close(); // 앱 종료 시 리소스 해제
    _urlController.dispose();
    super.dispose();
  }

  /// 사용자가 입력한 URL을 분석하고 다운로드를 시작하는 메인 함수
  Future<void> _startDownload() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      setState(() => _status = 'URL을 입력해주세요.');
      return;
    }

    // 모바일 환경에서 저장소 접근 권한을 확인
    if (!kIsWeb && Platform.isAndroid) {
      if (await Permission.storage.request().isDenied) {
        if (await Permission.videos.request().isDenied) {
          setState(() => _status = '저장소 권한이 거부되었습니다.');
          return;
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _status = '정보를 확인하는 중...';
      _progress = 0;
      _lastSavedPath = '';
    });

    try {
      List<Video> videos = [];
      String uploader = '';

      //  입력된 주소가 단일 영상인지 채널인지 판별하는 함수
      if (input.contains('watch?v=') || input.contains('youtu.be/')) {
        // 단일 동영상 주소가 입력된 경우
        final video = await _yt.videos.get(input);
        videos.add(video);
        uploader = video.author;
      } else {
        // 채널 주소 또는 핸들이 입력된 경우
        Channel channel;
        if (input.startsWith('@') && !input.contains('/')) {
          // @핸들 형식 처리
          channel = await _yt.channels.getByHandle(input);
        } else {
          try {
            channel = await _yt.channels.get(input);
          } catch (e) {
            // URL 안에 @핸들이 포함된 경우
            if (input.contains('/@')) {
              final handle = '@' + input.split('/@').last.split('?').first;
              channel = await _yt.channels.getByHandle(handle);
            } else {
              rethrow;
            }
          }
        }
        uploader = channel.title;
        setState(() => _status = '[$uploader] 채널 동영상 목록 가져오는 중...');
        // 채널의 모든 업로드 영상을 리스트로 가져옵니다.
        videos = await _yt.channels.getUploads(channel.id).toList();
      }

      if (videos.isEmpty) {
        setState(() {
          _isDownloading = false;
          _status = '다운로드 가능한 동영상이 없습니다.';
        });
        return;
      }

      //  저장할 폴더 이름을 정제하고 경로를 생성
      final safeUploader = uploader.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');

      String savePathStr = '';
      if (!kIsWeb) {
        Directory? directory;
        if (Platform.isAndroid) {
          // 안드로이드는 기본 다운로드 폴더 사용
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          // 데스크톰톰은 시스템 다운로드 폴더 사용
          directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        }

        // 채널명으로 폴더 생성
        final saveDir = Directory(p.join(directory!.path, safeUploader));
        if (!await saveDir.exists()) {
          await saveDir.create(recursive: true);
        }
        savePathStr = saveDir.path;
      } else {
        savePathStr = '브라우저 다운로드 폴더';
      }

      setState(() {
        _status = videos.length == 1
            ? '동영상 다운로드 준비 중...'
            : '[$uploader] 다운로드 시작 (총 ${videos.length}개)';
        _lastSavedPath = savePathStr;
      });

      // 수집된 영상 리스트를 순회하며 하나씩 다운로드
      int successCount = 0;
      for (var i = 0; i < videos.length; i++) {
        final video = videos[i];
        setState(() {
          _status = videos.length == 1
              ? '다운로드 중...'
              : '다운로드 중 (${i + 1}/${videos.length})';
          _currentFileName = video.title;
          _progress = i / videos.length;
        });

        bool success = await _downloadVideo(video, savePathStr);
        if (success) successCount++;

        // 웹 환경에서는 연속 다운로드 시 브라우저 차단을 피하기 위해 약간의 대기 시간을 둠
        if (kIsWeb) await Future.delayed(const Duration(milliseconds: 500));
      }

      setState(() {
        _isDownloading = false;
        _progress = 1.0;
        _status = videos.length == 1
            ? '다운로드 완료!'
            : '작업 완료! $successCount개의 파일을 처리했습니다.';
        _currentFileName = '';
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _status = '오류 발생: $e';
      });
    }
  }

  /// 개별 동영상의 스트림 데이터를 가져와 실제로 파일로 저장하는 함수
  Future<bool> _downloadVideo(Video video, String savePath) async {
    try {
      // 영상의 다양한 스트림 정보를 가져옴
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      // 오디오와 비디오가 합쳐진 가장 높은 화질의 스트림을 선택함
      final streamInfo = manifest.muxed.withHighestBitrate();

      if (streamInfo != null) {
        // 파일 이름에서 사용할 수 없는 특수문자를 제거함함
        final baseName = video.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
        String fileName = '$baseName.mp4';

        if (kIsWeb) {
          // 웹에서 데이터를 메모리에 모은 후 브라우저의 다운로드 기능을 트리거함함
          final stream = _yt.videos.streamsClient.get(streamInfo);
          List<int> bytes = [];
          await for (var chunk in stream) {
            bytes.addAll(chunk);
          }

          final blob = html.Blob([bytes], 'video/mp4');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', fileName)
            ..click();
          html.Url.revokeObjectUrl(url);
          return true;
        } else {
          //  중복 파일 이름 처리 로직
          String finalPath = p.join(savePath, fileName);
          int counter = 1;

          // 동일한 이름의 파일이 이미 폴더에 존재한다면 이름을 변경함 
          while (File(finalPath).existsSync()) {
            fileName = '${baseName}_$counter.mp4';
            finalPath = p.join(savePath, fileName);
            counter++;
          }

          // 파일 시스템에 직접 스트림 데이터를 씀씀
          final stream = _yt.videos.streamsClient.get(streamInfo);
          final file = File(finalPath);
          final fileStream = file.openWrite();
          await stream.pipe(fileStream); // 스트림 데이터를 파일에 연결
          await fileStream.flush();
          await fileStream.close();
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('다운로드 실패: ${video.title}, 사유: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YT_D'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 웹 모드일 때만 표시되는 안내 문구
            if (kIsWeb)
              const Card(
                color: Colors.blue,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('ℹ️ 웹 모드: 여러 파일을 다운로드할 때 브라우저가 "여러 파일 다운로드 허용"을 물어볼 수 있습니다. 허용해 주세요.',
                      style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ),
            const SizedBox(height: 10),
            // URL 입력창
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '채널/동영상 URL 또는 @핸들 입력',
                hintText: 'https://www.youtube.com/watch?v=... 또는 @handle',
                border: OutlineInputBorder(),
              ),
              enabled: !_isDownloading,
            ),
            const SizedBox(height: 20),
            // 실행 버튼
            ElevatedButton.icon(
              onPressed: _isDownloading ? null : _startDownload,
              icon: const Icon(Icons.download),
              label: const Text('다운로드 시작'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 30),
            // 진행 상황 표시 카드
            if (_status.isNotEmpty)
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (_lastSavedPath.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText('저장 대상: $_lastSavedPath', style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                      ],
                      if (_currentFileName.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('파일 처리 중: $_currentFileName',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 15),
                        LinearProgressIndicator(value: _progress),
                      ]
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

