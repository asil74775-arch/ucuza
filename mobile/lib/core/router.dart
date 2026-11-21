import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accessories/accessory_finder_screen.dart';
import '../features/ai/alternatives_screen.dart';
import '../features/ai/assistant_hub_screen.dart';
import '../features/ai/chat_screen.dart';
import '../features/ai/duel_screen.dart';
import '../features/ai/mission_screen.dart';
import '../features/ai/project_screen.dart';
import '../features/ai/should_buy_screen.dart';
import '../features/ar/ar_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/catalog/category_screen.dart';
import '../features/home/home_screen.dart';
import '../features/legal/admin_screen.dart';
import '../features/legal/notice_screen.dart';
import '../features/messages/chat_thread_screen.dart';
import '../features/messages/conversations_screen.dart';
import '../features/product/product_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/taste_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/social/create_experience_screen.dart';
import '../features/social/explore_screen.dart';
import '../features/social/qa_screen.dart';
import '../features/ai/photo_search_screen.dart';
import '../features/video/video_screen.dart';
import 'session.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authProvider.notifier);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth.changes,
    redirect: (context, state) {
      final s = ref.read(authProvider);
      if (!s.ready) return null;
      final loc = state.matchedLocation;
      final public = loc == '/login' || loc == '/onboarding';
      if (!s.loggedIn && !public) return '/onboarding';
      if (s.loggedIn && public) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, s) => LoginScreen(interests: s.extra as List<String>? ?? const [])),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (_, __) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/assistant', builder: (_, __) => const AssistantHubScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (_, __) => const CartScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: '/category/:id',
        builder: (_, s) => CategoryScreen(
          categoryId: int.tryParse(s.pathParameters['id']!) ?? 0,
          initialQuery: s.uri.queryParameters['q'],
        ),
      ),
      GoRoute(path: '/search', builder: (_, s) => CategoryScreen(categoryId: 0, initialQuery: s.uri.queryParameters['q'])),
      GoRoute(path: '/product/:id', builder: (_, s) => ProductScreen(id: int.parse(s.pathParameters['id']!))),
      GoRoute(path: '/product/:id/qa', builder: (_, s) => QaScreen(productId: int.parse(s.pathParameters['id']!))),
      GoRoute(path: '/product/:id/alternatives', builder: (_, s) => AlternativesScreen(productId: int.parse(s.pathParameters['id']!))),
      GoRoute(path: '/product/:id/share', builder: (_, s) => CreateExperienceScreen(productId: int.parse(s.pathParameters['id']!))),
      GoRoute(path: '/ar', builder: (_, s) => ArScreen(product: s.extra as Map<String, dynamic>)),
      GoRoute(path: '/accessories', builder: (_, __) => const AccessoryFinderScreen()),
      GoRoute(path: '/ai/chat', builder: (_, __) => const ChatScreen()),
      GoRoute(path: '/ai/should-buy', builder: (_, s) => ShouldBuyScreen(product: s.extra as Map<String, dynamic>?)),
      GoRoute(path: '/ai/mission', builder: (_, __) => const MissionScreen()),
      GoRoute(path: '/ai/project', builder: (_, __) => const ProjectScreen()),
      GoRoute(path: '/ai/duel', builder: (_, s) => DuelScreen(initialA: s.extra as Map<String, dynamic>?)),
      GoRoute(path: '/ai/video', builder: (_, __) => const VideoScreen()),
      GoRoute(path: '/ai/photo-search', builder: (_, __) => const PhotoSearchScreen()),
      GoRoute(path: '/messages', builder: (_, __) => const ConversationsScreen()),
      GoRoute(
        path: '/messages/:id',
        builder: (_, s) => ChatThreadScreen(conversationId: int.parse(s.pathParameters['id']!), title: s.extra as String? ?? 'Sohbet'),
      ),
      GoRoute(path: '/taste', builder: (_, __) => const TasteScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
      GoRoute(path: '/notice', builder: (_, s) => NoticeScreen(target: s.extra as Map<String, dynamic>?)),
    ],
  );
});
