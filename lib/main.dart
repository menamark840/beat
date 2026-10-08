import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const App());

const bg = Color(0xFF0B0B10);
final player = AudioPlayer();
final query = OnAudioQuery();
final current = ValueNotifier<SongModel?>(null);
List<SongModel> queue = [];

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Beat',
        theme: ThemeData.dark(useMaterial3: true)
            .copyWith(scaffoldBackgroundColor: bg),
        home: const Home(),
      );
}

// لون مميز لكل أغنية
Color accent(SongModel? s) => HSLColor.fromAHSL(
        1, (((s?.id ?? 0) * 47) % 360).toDouble(), .65, .45)
    .toColor();

String fmt(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

Widget art(int id, double size, {double r = 12}) => QueryArtworkWidget(
      id: id,
      type: ArtworkType.AUDIO,
      size: 500,
      quality: 90,
      artworkWidth: size,
      artworkHeight: size,
      artworkFit: BoxFit.cover,
      artworkBorder: BorderRadius.circular(r),
      nullArtworkWidget: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: Colors.white10, borderRadius: BorderRadius.circular(r)),
        child: const Icon(Icons.music_note, color: Colors.white38),
      ),
    );

Future<void> playList(List<SongModel> list, int i) async {
  queue = list;
  await player.setAudioSource(ConcatenatingAudioSource(
      children: [for (final s in list) AudioSource.uri(Uri.parse(s.uri!))]),
      initialIndex: i);
  current.value = list[i];
  player.play();
}

// الذكاء: أي أغنية من غير ألبوم حقيقي تتجمع تلقائي مع أغاني نفس الفنان
class Album {
  final String name, artist;
  final List<SongModel> songs;
  Album(this.name, this.artist, this.songs);
}

List<Album> buildAlbums(List<SongModel> all) {
  const bad = {'', '<unknown>', 'unknown', 'download', 'downloads', 'music', '0'};
  final map = <String, Album>{};
  for (final s in all) {
    final ar = (s.artist == null || s.artist!.toLowerCase() == '<unknown>')
        ? 'Unknown'
        : s.artist!.trim();
    final al = (s.album ?? '').trim();
    final name = bad.contains(al.toLowerCase()) ? '$ar · Collection' : al;
    map.putIfAbsent('$ar|$name', () => Album(name, ar, [])).songs.add(s);
  }
  return map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<SongModel> songs = [];
  List<Album> albums = [];
  bool loading = true, denied = false;

  @override
  void initState() {
    super.initState();
    player.currentIndexStream.listen((i) {
      if (i != null && i < queue.length) current.value = queue[i];
    });
    load();
  }

  Future<void> load() async {
    var st = await Permission.audio.request();
    if (!st.isGranted) st = await Permission.storage.request();
    if (!st.isGranted) {
      setState(() {
        loading = false;
        denied = true;
      });
      return;
    }
    final all = await query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true);
    songs = all.where((x) => (x.duration ?? 0) > 30000).toList();
    albums = buildAlbums(songs);
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext c) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (denied) {
      return Scaffold(
          body: Center(
              child: FilledButton(
                  onPressed: openAppSettings,
                  child: const Text('اسمح بالوصول للأغاني'))));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Beat',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
          bottom: const TabBar(
              indicatorColor: Color(0xFF8B5CF6),
              tabs: [Tab(text: 'Songs'), Tab(text: 'Albums')]),
        ),
        body: TabBarView(children: [songList(songs), albumGrid(c)]),
        bottomNavigationBar: const MiniPlayer(),
      ),
    );
  }

  Widget albumGrid(BuildContext c) => GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: .8),
        itemCount: albums.length,
        itemBuilder: (_, i) {
          final a = albums[i];
          return GestureDetector(
            onTap: () => Navigator.push(
                c,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(a.name)),
                        body: songList(a.songs)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: LayoutBuilder(
                      builder: (_, k) => art(a.songs.first.id, k.maxWidth, r: 18))),
              const SizedBox(height: 6),
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${a.artist} · ${a.songs.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          );
        },
      );
}

Widget songList(List<SongModel> list) => ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final s = list[i];
        return ListTile(
          leading: art(s.id, 48),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(s.artist ?? 'Unknown',
              maxLines: 1, style: const TextStyle(color: Colors.white54)),
          onTap: () => playList(list, i),
        );
      },
    );

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<SongModel?>(
        valueListenable: current,
        builder: (_, s, __) {
          if (s == null) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => Navigator.push(
                c,
                PageRouteBuilder(
                  pageBuilder: (_, a, __) => const Full(),
                  transitionsBuilder: (_, a, __, child) => SlideTransition(
                      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                          .animate(CurvedAnimation(
                              parent: a, curve: Curves.easeOutCubic)),
                      child: child),
                )),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: accent(s).withOpacity(.35),
                  borderRadius: BorderRadius.circular(18)),
              child: SafeArea(
                top: false,
                child: Row(children: [
                  art(s.id, 44),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  StreamBuilder<bool>(
                      stream: player.playingStream,
                      builder: (_, p) => IconButton(
                          icon: Icon(p.data == true ? Icons.pause : Icons.play_arrow),
                          onPressed: () =>
                              p.data == true ? player.pause() : player.play())),
                ]),
              ),
            ),
          );
        },
      );
}

class Full extends StatelessWidget {
  const Full({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<SongModel?>(
        valueListenable: current,
        builder: (_, s, __) {
          final col = accent(s);
          return Scaffold(
            body: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [col.withOpacity(.8), bg])),
              child: SafeArea(
                child: Column(children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                          onPressed: () => Navigator.pop(c))),
                  const Spacer(),
                  if (s != null)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Container(
                        key: ValueKey(s.id),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                  color: col.withOpacity(.5),
                                  blurRadius: 40,
                                  spreadRadius: 2)
                            ]),
                        child: art(s.id, 300, r: 24),
                      ),
                    ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(children: [
                      Text(s?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(s?.artist ?? '',
                          style: const TextStyle(color: Colors.white60)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (_, p) {
                      final pos = p.data ?? Duration.zero;
                      final dur = player.duration ?? Duration.zero;
                      final m = max(1, dur.inMilliseconds);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(children: [
                          Slider(
                              value: pos.inMilliseconds.clamp(0, m).toDouble(),
                              max: m.toDouble(),
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                              onChanged: (v) =>
                                  player.seek(Duration(milliseconds: v.toInt()))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [Text(fmt(pos)), Text(fmt(dur))]),
                          ),
                        ]),
                      );
                    },
                  ),
                  StreamBuilder<bool>(
                    stream: player.playingStream,
                    builder: (_, p) {
                      final playing = p.data == true;
                      return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                iconSize: 40,
                                icon: const Icon(Icons.skip_previous),
                                onPressed: player.seekToPrevious),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => playing ? player.pause() : player.play(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: playing ? 76 : 68,
                                height: playing ? 76 : 68,
                                decoration: const BoxDecoration(
                                    color: Colors.white, shape: BoxShape.circle),
                                child: Icon(playing ? Icons.pause : Icons.play_arrow,
                                    size: 40, color: Colors.black),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                                iconSize: 40,
                                icon: const Icon(Icons.skip_next),
                                onPressed: player.seekToNext),
                          ]);
                    },
                  ),
                  const Spacer(),
                ]),
              ),
            ),
          );
        },
      );
}
