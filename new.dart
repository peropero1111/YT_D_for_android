Future<void> _startDownload() async {
  // 1. 공백 제거 및 특수문자 정제
  final url = _urlController.text.trim();
  if (url.isEmpty) {
    setState(() => _status = 'URL을 입력해주세요.');
    return;
  }

  // 권한 요청 (모바일 전용) 생략...
  if (!kIsWeb && Platform.isAndroid) {
    if (await Permission.storage
        .request()
        .isDenied) {
      if (await Permission.videos
          .request()
          .isDenied) {
        setState(() => _status = '저장소 권한이 거부되었습니다.');
        return;
      }
    }
  }

  setState(() {
    _isDownloading = true;
    _status = '정보를 가져오는 중...';
    _progress = 0;
    _lastSavedPath = '';
  });

  try {
    Channel channel;

    // 2. 주소 형식에 따른 처리 분기
    if (url.contains('watch?v=') || url.contains('youtu.be/')) {
      // 동영상 주소가 입력된 경우, 해당 영상의 채널 정보를 가져옴
      final video = await _yt.videos.get(url);
      channel = await _yt.channels.get(video.channelId);
    } else if (url.startsWith('@') && !url.contains('youtube.com')) {
      // @핸들만 입력된 경우 (예: @Google)
      channel = await _yt.channels.getByHandle(url);
    } else {
      // 일반 채널 URL 또는 ID
      channel = await _yt.channels.get(url);
    }

    final uploader = channel.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');

    // 저장 경로 설정 로직... (기존과 동일)
    String savePathStr = '';
    if (!kIsWeb) {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }
      final saveDir = Directory(p.join(directory!.path, uploader));
      if (!await saveDir.exists()) await saveDir.create(recursive: true);
      savePathStr = saveDir.path;
    }

    setState(() {
      _status = '[$uploader] 동영상 목록 검색 중...';
      _lastSavedPath = savePathStr;
    });

    // 동영상 목록 가져오기
    final videos = await _yt.channels.getUploads(channel.id).toList();
  // ... 이후 다운로드 로직은 기존과 동일