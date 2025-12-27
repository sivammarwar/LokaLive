import SEOHandler from '@/components/seo/SEOHandler';

const OnlineMultiplayerGamePage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-blue-900/20">
      <SEOHandler />
      <div className="container mx-auto px-4 py-16">
        <h1 className="text-4xl md:text-5xl font-bold text-center mb-6">
          Online Multiplayer Games | Play with Real Users Worldwide
        </h1>
        
        <div className="glass rounded-3xl p-8 max-w-4xl mx-auto">
          <p className="text-lg mb-6">
            Experience the future of online gaming with LOKA's multiplayer platform. Play real-time games with strangers while chatting via video. No downloads, no registration - just instant fun!
          </p>
          
          <div className="grid md:grid-cols-2 gap-8 mt-8">
            <div>
              <h2 className="text-2xl font-bold mb-4">Why Choose LOKA for Gaming?</h2>
              <ul className="space-y-3">
                <li className="flex items-center gap-3">✅ <span>Real human opponents (no bots)</span></li>
                <li className="flex items-center gap-3">✅ <span>Live video chat during gameplay</span></li>
                <li className="flex items-center gap-3">✅ <span>Play for diamonds in bet matches</span></li>
                <li className="flex items-center gap-3">✅ <span>Instant matchmaking</span></li>
                <li className="flex items-center gap-3">✅ <span>Works on all devices</span></li>
              </ul>
            </div>
            
            <div>
              <h2 className="text-2xl font-bold mb-4">Available Games</h2>
              <ul className="space-y-3">
                <li className="flex items-center gap-3">♟️ <span className="font-medium">Chess - With video chat</span></li>
                <li className="flex items-center gap-3">🎯 <span className="font-medium">More games coming soon!</span></li>
                <li className="flex items-center gap-3">💡 <span className="text-muted-foreground">Suggest your favorite games</span></li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OnlineMultiplayerGamePage;