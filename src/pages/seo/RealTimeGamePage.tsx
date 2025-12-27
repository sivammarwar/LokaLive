import SEOHandler from '@/components/seo/SEOHandler';
import { Button } from '@/components/ui/button';
import { Zap, Clock, Wifi, Users, Shield } from 'lucide-react';

const RealTimeGamePage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-purple-900/20">
      <SEOHandler />
      <div className="container mx-auto px-4 py-12 md:py-16">
        <div className="text-center mb-12">
          <h1 className="text-4xl md:text-5xl font-bold mb-4 bg-gradient-to-r from-purple-600 to-pink-500 bg-clip-text text-transparent">
            Real-Time Games Online | Zero Lag Multiplayer
          </h1>
          <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
            Experience smooth, lag-free multiplayer gaming with instant responses. Play chess and other games in real-time with live opponents.
          </p>
        </div>

        <div className="grid lg:grid-cols-2 gap-8 mb-12">
          <div className="glass rounded-3xl p-8">
            <h2 className="text-3xl font-bold mb-6">Why Real-Time Gaming Matters</h2>
            <div className="space-y-6">
              {[
                {
                  icon: <Zap className="h-6 w-6 text-yellow-500" />,
                  title: "Instant Responses",
                  desc: "No delay between moves. See your opponent's actions immediately."
                },
                {
                  icon: <Clock className="h-6 w-6 text-blue-500" />,
                  title: "Live Timer",
                  desc: "Real-time chess clocks for competitive matches with time control."
                },
                {
                  icon: <Wifi className="h-6 w-6 text-green-500" />,
                  title: "Low Latency",
                  desc: "Optimized servers ensure minimal delay for smooth gameplay."
                },
                {
                  icon: <Users className="h-6 w-6 text-purple-500" />,
                  title: "Live Opponents",
                  desc: "Real people playing in real-time, not AI with simulated delays."
                }
              ].map((item, i) => (
                <div key={i} className="flex items-start gap-4">
                  <div className="w-12 h-12 rounded-xl bg-muted flex items-center justify-center flex-shrink-0">
                    {item.icon}
                  </div>
                  <div>
                    <h3 className="text-lg font-bold mb-1">{item.title}</h3>
                    <p className="text-muted-foreground">{item.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="glass rounded-3xl p-8">
            <h2 className="text-3xl font-bold mb-6">Technical Excellence</h2>
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-500/20">
                <h4 className="font-bold mb-2">WebRTC Technology</h4>
                <p className="text-sm">Peer-to-peer connections ensure minimal latency and maximum speed for real-time gaming.</p>
              </div>
              
              <div className="p-4 rounded-xl bg-blue-500/10 border border-blue-500/20">
                <h4 className="font-bold mb-2">Global Servers</h4>
                <p className="text-sm">Servers worldwide to match you with nearby opponents for the best connection.</p>
              </div>
              
              <div className="p-4 rounded-xl bg-green-500/10 border border-green-500/20">
                <h4 className="font-bold mb-2">Connection Stability</h4>
                <p className="text-sm">Automatic reconnection and game state preservation if connection drops.</p>
              </div>
            </div>
          </div>
        </div>

        <div className="text-center glass rounded-3xl p-8">
          <h2 className="text-3xl font-bold mb-4">Experience Real-Time Gaming</h2>
          <p className="text-xl text-muted-foreground mb-8 max-w-2xl mx-auto">
            Feel the difference of true real-time multiplayer. No artificial delays, just pure gaming action.
          </p>
          <Button size="lg" className="px-10 py-7 text-lg bg-gradient-to-r from-purple-600 to-pink-600">
            Start Real-Time Gaming
          </Button>
        </div>
      </div>
    </div>
  );
};

export default RealTimeGamePage;