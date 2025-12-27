import SEOHandler from '@/components/seo/SEOHandler';
import { Button } from '@/components/ui/button';
import { Video, MessageSquare, Users, Trophy, Brain, Globe } from 'lucide-react';

const PlayChessWithVideoChatPage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-amber-900/10">
      <SEOHandler />
      <div className="container mx-auto px-4 py-12 md:py-16">
        <div className="text-center mb-12">
          <div className="inline-flex items-center gap-4 mb-6">
            <div className="w-16 h-16 rounded-full bg-amber-500/20 flex items-center justify-center">
              <span className="text-3xl">♟️</span>
            </div>
            <div className="w-16 h-16 rounded-full bg-blue-500/20 flex items-center justify-center">
              <Video className="h-8 w-8 text-blue-500" />
            </div>
          </div>
          <h1 className="text-4xl md:text-5xl font-bold mb-4 bg-gradient-to-r from-amber-600 to-blue-600 bg-clip-text text-transparent">
            Play Chess with Video Chat | See Your Opponent Live
          </h1>
          <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
            The ultimate chess experience: face-to-face gaming with live video chat. Read emotions, discuss moves, and connect with chess enthusiasts worldwide.
          </p>
        </div>

        <div className="grid md:grid-cols-3 gap-6 mb-12">
          {[
            {
              icon: <Video className="h-8 w-8" />,
              title: "Face-to-Face",
              desc: "See your opponent's reactions to your brilliant moves"
            },
            {
              icon: <MessageSquare className="h-8 w-8" />,
              title: "Live Chat",
              desc: "Discuss strategies or just have friendly conversation"
            },
            {
              icon: <Brain className="h-8 w-8" />,
              title: "Mind Games",
              desc: "Read body language and facial expressions like real chess"
            }
          ].map((feature, i) => (
            <div key={i} className="glass rounded-2xl p-6 text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-primary/20 flex items-center justify-center">
                {feature.icon}
              </div>
              <h3 className="text-xl font-bold mb-2">{feature.title}</h3>
              <p className="text-muted-foreground">{feature.desc}</p>
            </div>
          ))}
        </div>

        <div className="glass rounded-3xl p-8 mb-12">
          <h2 className="text-3xl font-bold mb-8 text-center">Why Video Chat Makes Chess Better</h2>
          <div className="grid md:grid-cols-2 gap-8">
            <div>
              <h3 className="text-2xl font-bold mb-4">Social Chess Experience</h3>
              <p className="text-muted-foreground mb-4">
                Chess has always been a social game. With video chat, you can:
              </p>
              <ul className="space-y-3">
                <li className="flex items-center gap-3">✅ <span>Make new chess friends worldwide</span></li>
                <li className="flex items-center gap-3">✅ <span>Learn from opponents' strategies</span></li>
                <li className="flex items-center gap-3">✅ <span>Share tips and improve together</span></li>
                <li className="flex items-center gap-3">✅ <span>Experience the human side of chess</span></li>
              </ul>
            </div>
            
            <div>
              <h3 className="text-2xl font-bold mb-4">Competitive Edge</h3>
              <p className="text-muted-foreground mb-4">
                Video chat adds a new dimension to competitive play:
              </p>
              <ul className="space-y-3">
                <li className="flex items-center gap-3">🎯 <span>Psychological advantage through visual cues</span></li>
                <li className="flex items-center gap-3">🎯 <span>Post-game analysis with opponents</span></li>
                <li className="flex items-center gap-3">🎯 <span>Build reputation in the chess community</span></li>
                <li className="flex items-center gap-3">🎯 <span>Participate in live chess tournaments</span></li>
              </ul>
            </div>
          </div>
        </div>

        <div className="text-center">
          <Button size="lg" className="text-lg px-10 py-7 bg-gradient-to-r from-amber-600 to-blue-600">
            Start Playing Chess with Video Chat
          </Button>
          <p className="text-sm text-muted-foreground mt-4">
            No webcam? You can still play with audio chat or text only!
          </p>
        </div>
      </div>
    </div>
  );
};

export default PlayChessWithVideoChatPage;