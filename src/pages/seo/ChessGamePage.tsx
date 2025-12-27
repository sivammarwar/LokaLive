import SEOHandler from '@/components/seo/SEOHandler';
import { Button } from '@/components/ui/button';
import {Crown, Trophy, Video, Users, Zap, Shield } from 'lucide-react';

const ChessGamePage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-amber-900/10">
      <SEOHandler />
      <div className="container mx-auto px-4 py-12 md:py-16">
        {/* Hero Section */}
        <div className="text-center mb-12">
          <div className="inline-flex items-center gap-3 mb-6">
            <div className="w-16 h-16 rounded-full bg-amber-500/20 flex items-center justify-center">
              <Crown className="h-10 w-10 text-amber-500" />
            </div>
            <h1 className="text-4xl md:text-5xl font-bold bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">
              Play Chess Online with Video Chat
            </h1>
          </div>
          <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
            Challenge strangers to chess matches while chatting face-to-face. Real-time multiplayer chess with voice and video communication.
          </p>
        </div>

        {/* Main Features */}
        <div className="grid lg:grid-cols-2 gap-8 mb-12">
          <div className="glass rounded-3xl p-8">
            <h2 className="text-3xl font-bold mb-6">Features That Make Chess Exciting</h2>
            
            <div className="space-y-6">
              {[
                {
                  icon: <Video className="h-6 w-6 text-blue-500" />,
                  title: "Live Video Chat",
                  desc: "See your opponent and talk strategy during the game"
                },
                {
                  icon: <Trophy className="h-6 w-6 text-amber-500" />,
                  title: "Bet Matches",
                  desc: "Play for diamonds. Winner takes all in exciting bet matches"
                },
                {
                  icon: <Zap className="h-6 w-6 text-purple-500" />,
                  title: "Instant Matching",
                  desc: "Find chess partners in seconds. No waiting, just play"
                },
                {
                  icon: <Shield className="h-6 w-6 text-green-500" />,
                  title: "Fair Play",
                  desc: "Anti-cheat system ensures fair and competitive matches"
                }
              ].map((feature, i) => (
                <div key={i} className="flex items-start gap-4">
                  <div className="w-12 h-12 rounded-xl bg-muted flex items-center justify-center flex-shrink-0">
                    {feature.icon}
                  </div>
                  <div>
                    <h3 className="text-lg font-bold mb-1">{feature.title}</h3>
                    <p className="text-muted-foreground">{feature.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="glass rounded-3xl p-8">
            <h2 className="text-3xl font-bold mb-6">Why Play Chess on LOKA?</h2>
            
            <div className="space-y-4 mb-8">
              <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-500/20">
                <h4 className="font-bold mb-2 flex items-center gap-2">
                  <Users className="h-5 w-5" /> Social Gaming
                </h4>
                <p className="text-sm">Meet new people from around the world while playing chess. Make friends, learn strategies, and have fun conversations.</p>
              </div>
              
              <div className="p-4 rounded-xl bg-blue-500/10 border border-blue-500/20">
                <h4 className="font-bold mb-2 flex items-center gap-2">
                  <Trophy className="h-5 w-5" /> Competitive Play
                </h4>
                <p className="text-sm">Compete in diamond bet matches. Test your skills against real opponents and win rewards for your victories.</p>
              </div>
              
              <div className="p-4 rounded-xl bg-green-500/10 border border-green-500/20">
                <h4 className="font-bold mb-2">No Registration Needed</h4>
                <p className="text-sm">Start playing immediately without any sign-up. Just click and play chess with strangers instantly.</p>
              </div>
            </div>

            <div className="text-center">
              <Button size="lg" className="w-full py-6 text-lg">
                Play Chess Now - It's Free!
              </Button>
              <p className="text-xs text-muted-foreground mt-2">
                No download required • Works on all devices • Beginner-friendly
              </p>
            </div>
          </div>
        </div>

        {/* Game Modes */}
        <div className="glass rounded-3xl p-8 mb-12">
          <h2 className="text-3xl font-bold mb-8 text-center">Choose Your Game Mode</h2>
          <div className="grid md:grid-cols-3 gap-6">
            {[
              {
                title: "Casual Chess",
                desc: "Friendly matches with strangers",
                features: ["No pressure", "Make friends", "Learn together"],
                color: "bg-blue-500/10"
              },
              {
                title: "Bet Matches",
                desc: "Play for diamonds",
                features: ["Winner takes all", "Exciting stakes", "Rank up"],
                color: "bg-amber-500/10"
              },
              {
                title: "Tournaments",
                desc: "Coming soon",
                features: ["Multiple opponents", "Big prizes", "Leaderboards"],
                color: "bg-purple-500/10"
              }
            ].map((mode, i) => (
              <div key={i} className={`rounded-2xl p-6 ${mode.color} border border-muted`}>
                <h3 className="text-xl font-bold mb-2">{mode.title}</h3>
                <p className="text-muted-foreground mb-4">{mode.desc}</p>
                <ul className="space-y-2">
                  {mode.features.map((feature, j) => (
                    <li key={j} className="flex items-center gap-2 text-sm">
                      <div className="w-2 h-2 rounded-full bg-primary"></div>
                      {feature}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>

        {/* FAQ */}
        <div className="mb-12">
          <h2 className="text-3xl font-bold mb-8 text-center">Frequently Asked Questions</h2>
          <div className="grid md:grid-cols-2 gap-6 max-w-4xl mx-auto">
            {[
              {
                q: "Do I need to know how to play chess?",
                a: "All skill levels are welcome! We have players from complete beginners to experienced chess enthusiasts."
              },
              {
                q: "Is video chat mandatory?",
                a: "No, you can disable your camera anytime. But video chat makes the experience more social and fun!"
              },
              {
                q: "How do bet matches work?",
                a: "Both players put up equal diamonds. Winner takes all diamonds after the match ends."
              },
              {
                q: "Can I play on mobile?",
                a: "Yes! LOKA works perfectly on smartphones, tablets, and desktop computers."
              }
            ].map((faq, i) => (
              <div key={i} className="bg-card/50 rounded-xl p-6">
                <h3 className="font-bold mb-2">{faq.q}</h3>
                <p className="text-muted-foreground">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Final CTA */}
        <div className="text-center glass rounded-3xl p-8">
          <h2 className="text-3xl font-bold mb-4">Ready to Play Chess?</h2>
          <p className="text-xl text-muted-foreground mb-8 max-w-2xl mx-auto">
            Join thousands of players enjoying chess with video chat. No registration, no download - just instant fun!
          </p>
          <Button size="lg" className="px-10 py-7 text-lg">
            Start Playing Chess Now
          </Button>
        </div>
      </div>
    </div>
  );
};

export default ChessGamePage;