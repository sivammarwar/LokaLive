import SEOHandler from '@/components/seo/SEOHandler';
import { Button } from '@/components/ui/button';
import { Users, Gamepad2, Trophy, Shield, Clock, Globe } from 'lucide-react';

const MultiplayerGamePage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-purple-900/20">
      <SEOHandler />
      <div className="container mx-auto px-4 py-12 md:py-16">
        {/* Hero Section */}
        <div className="text-center mb-12">
          <h1 className="text-4xl md:text-5xl font-bold mb-4 bg-gradient-to-r from-primary to-purple-500 bg-clip-text text-transparent">
            Multiplayer Games Online | Play with Real People
          </h1>
          <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
            Experience the thrill of real-time multiplayer gaming with video chat. Play games with strangers from around the world!
          </p>
        </div>

        {/* Features Grid */}
        <div className="grid md:grid-cols-3 gap-8 mb-12">
          <div className="glass rounded-2xl p-6 text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-purple-500/20 flex items-center justify-center">
              <Users className="h-8 w-8 text-purple-400" />
            </div>
            <h3 className="text-xl font-bold mb-2">Real Players</h3>
            <p className="text-muted-foreground">Play against real people, not bots. Every game is a unique human experience.</p>
          </div>

          <div className="glass rounded-2xl p-6 text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-blue-500/20 flex items-center justify-center">
              <Gamepad2 className="h-8 w-8 text-blue-400" />
            </div>
            <h3 className="text-xl font-bold mb-2">Instant Matchmaking</h3>
            <p className="text-muted-foreground">Find opponents in seconds. No waiting, just instant gaming action.</p>
          </div>

          <div className="glass rounded-2xl p-6 text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-green-500/20 flex items-center justify-center">
              <Trophy className="h-8 w-8 text-green-400" />
            </div>
            <h3 className="text-xl font-bold mb-2">Win Diamonds</h3>
            <p className="text-muted-foreground">Compete in bet matches and win real diamonds. Play to earn rewards!</p>
          </div>
        </div>

        {/* Game Types */}
        <div className="glass rounded-3xl p-8 mb-12">
          <h2 className="text-3xl font-bold mb-8 text-center">Available Games</h2>
          <div className="grid md:grid-cols-2 gap-6">
            <div className="bg-card/50 rounded-xl p-6 border border-primary/20">
              <div className="flex items-center gap-4 mb-4">
                <div className="w-12 h-12 rounded-lg bg-amber-500/20 flex items-center justify-center">
                  <span className="text-2xl">♟️</span>
                </div>
                <div>
                  <h3 className="text-xl font-bold">Chess</h3>
                  <p className="text-sm text-muted-foreground">Classic Strategy Game</p>
                </div>
              </div>
              <p className="text-muted-foreground mb-4">
                Challenge strangers to chess matches with live video chat. Bet diamonds to make it more exciting!
              </p>
              <Button className="w-full">Play Chess Now</Button>
            </div>

            <div className="bg-card/50 rounded-xl p-6 border border-primary/20">
              <div className="flex items-center gap-4 mb-4">
                <div className="w-12 h-12 rounded-lg bg-blue-500/20 flex items-center justify-center">
                  <span className="text-2xl">🎯</span>
                </div>
                <div>
                  <h3 className="text-xl font-bold">More Games Coming</h3>
                  <p className="text-sm text-muted-foreground">Checkers, Tic-Tac-Toe, Cards</p>
                </div>
              </div>
              <p className="text-muted-foreground mb-4">
                We're constantly adding new multiplayer games. Suggest your favorite games and help us build the ultimate gaming platform.
              </p>
              <Button variant="outline" className="w-full">Suggest a Game</Button>
            </div>
          </div>
        </div>

        {/* How It Works */}
        <div className="mb-12">
          <h2 className="text-3xl font-bold mb-8 text-center">How to Play</h2>
          <div className="grid md:grid-cols-4 gap-6">
            {[
              { icon: <Users />, title: "Join Room", desc: "Enter a video chat room with other players" },
              { icon: <Gamepad2 />, title: "Challenge", desc: "Send game invitation to any participant" },
              { icon: <Clock />, title: "Play Live", desc: "Start playing in real-time with video chat" },
              { icon: <Trophy />, title: "Win Rewards", desc: "Earn diamonds and climb leaderboards" }
            ].map((step, i) => (
              <div key={i} className="text-center">
                <div className="w-14 h-14 mx-auto mb-4 rounded-full bg-primary/20 flex items-center justify-center">
                  {step.icon}
                </div>
                <h3 className="font-bold mb-2">{step.title}</h3>
                <p className="text-sm text-muted-foreground">{step.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {/* CTA */}
        <div className="text-center">
          <Button size="lg" className="text-lg px-8 py-6">
            Start Playing Multiplayer Games
          </Button>
          <p className="text-sm text-muted-foreground mt-4">
            No registration required • Free to play • Instant matching
          </p>
        </div>
      </div>
    </div>
  );
};

export default MultiplayerGamePage;