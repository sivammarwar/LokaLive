import SEOHandler from '@/components/seo/SEOHandler';

const PlayWithRealUserPage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-green-900/20">
      <SEOHandler />
      <div className="container mx-auto px-4 py-16">
        <h1 className="text-4xl md:text-5xl font-bold text-center mb-6">
          Play Games with Real Users | Human Opponents Online
        </h1>
        
        <div className="glass rounded-3xl p-8 max-w-4xl mx-auto">
          <p className="text-xl text-center mb-8">
            Tired of playing against boring AI bots? Experience the thrill of competing against real human opponents!
          </p>
          
          <div className="space-y-6">
            <div className="p-6 rounded-2xl bg-card/50">
              <h2 className="text-2xl font-bold mb-3">Real People, Real Emotions</h2>
              <p>
                Every game on LOKA is played against real human beings. See their reactions through video chat, hear their excitement, and experience genuine human competition.
              </p>
            </div>
            
            <div className="p-6 rounded-2xl bg-card/50">
              <h2 className="text-2xl font-bold mb-3">Make Friends While Gaming</h2>
              <p>
                Gaming is more fun when you can socialize. Chat with your opponents, discuss strategies, and make new friends from around the world.
              </p>
            </div>
            
            <div className="p-6 rounded-2xl bg-card/50">
              <h2 className="text-2xl font-bold mb-3">Fair Competition</h2>
              <p>
                Our platform ensures fair play. No cheating bots, no unfair advantages - just pure skill-based competition between real players.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PlayWithRealUserPage;