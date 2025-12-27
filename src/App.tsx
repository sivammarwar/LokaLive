import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { HelmetProvider } from "react-helmet-async"; // ✅ ADD THIS IMPORT
import Index from "./pages/Index";
import CreateRoom from "./pages/CreateRoom";
import Room from "./pages/Room";
import Premium from "./pages/Premium";
import DiamondPurchase from "./pages/DiamondPurchase";
import DiamondWithdrawal from "./pages/DiamondWithdrawal";
import NotFound from "./pages/NotFound";

// Import all SEO pages from seo folder
import OmegleAlternativePage from "./pages/seo/OmegleAlternative";
import OmetvAlternativePage from "./pages/seo/OmetvAlternative";
import LiveChatPage from "./pages/seo/LiveChat";
import RandomChatPage from "./pages/seo/RandomChat";
import NoLoginChatPage from "./pages/seo/NoLoginChat";
import EntertainmentChatPage from "./pages/seo/EntertainmentChat";
import MonkeyAlternativePage from "./pages/seo/MonkeyAlternative";
import ChatAppsComparisonPage from "./pages/seo/SocialComparison";
import MultiplayerGamePage from "./pages/seo/MultiplayerGamePage";
import ChessGamePage from "./pages/seo/ChessGamePage";
import OnlineMultiplayerGamePage from "./pages/seo/OnlineMultiplayerGamePage";
import PlayWithRealUserPage from "./pages/seo/PlayWithRealUserPage";
import RealTimeGamePage from "./pages/seo/RealTimeGamePage";
import PlayChessWithVideoChatPage from "./pages/seo/PlayChessWithVideoChatPage";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <HelmetProvider> {/* ✅ WRAP EVERYTHING WITH HelmetProvider */}
        <BrowserRouter>
          <Routes>
            {/* Main App Pages */}
            <Route path="/" element={<Index />} />
            <Route path="/create-room" element={<CreateRoom />} />
            <Route path="/room/:roomId" element={<Room />} />
            <Route path="/premium" element={<Premium />} />
            <Route path="/buy-diamonds" element={<DiamondPurchase />} />
            <Route path="/withdraw-diamonds" element={<DiamondWithdrawal />} />
            
            {/* SEO Pages - All in seo folder */}
            <Route path="/omegle-alternative" element={<OmegleAlternativePage />} />
            <Route path="/ometv-alternative" element={<OmetvAlternativePage />} />
            <Route path="/live-chat" element={<LiveChatPage />} />
            <Route path="/random-chat" element={<RandomChatPage />} />
            <Route path="/no-login-chat" element={<NoLoginChatPage />} />
            <Route path="/entertainment-chat" element={<EntertainmentChatPage />} />
            <Route path="/monkey-alternative" element={<MonkeyAlternativePage />} />
            <Route path="/chat-apps-comparison" element={<ChatAppsComparisonPage />} />
            
            {/* NEW Gaming SEO Pages */}
            <Route path="/multiplayer-games" element={<MultiplayerGamePage />} />
            <Route path="/chess-game" element={<ChessGamePage />} />
            <Route path="/online-multiplayer-game" element={<OnlineMultiplayerGamePage />} />
            <Route path="/play-with-real-user" element={<PlayWithRealUserPage />} />
            <Route path="/real-time-game" element={<RealTimeGamePage />} />
            <Route path="/play-chess-with-video-chat" element={<PlayChessWithVideoChatPage />} />
            
            {/* 404 */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </HelmetProvider>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;