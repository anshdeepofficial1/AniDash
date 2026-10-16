import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:go_router/go_router.dart';

class CustomVideoPlayerScreen extends StatefulWidget {
  final String url;

  const CustomVideoPlayerScreen({super.key, required this.url});

  @override
  State<CustomVideoPlayerScreen> createState() =>
      _CustomVideoPlayerScreenState();
}

class _CustomVideoPlayerScreenState extends State<CustomVideoPlayerScreen> {
  late final BetterPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        allowedScreenSleep: false,
      ),
      betterPlayerDataSource: BetterPlayerDataSource.file(widget.url),
    );
  }

  @override
  void dispose() {
    controller.dispose(forceDispose: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: BetterPlayer(controller: controller)),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}
