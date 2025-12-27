import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler'; // ✅ Imported
import { Link } from "react-router-dom";
import { Music, Gamepad2, Laugh, Film, Zap, Users } from "lucide-react";

const EntertainmentChat = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      {/* ✅ REMOVE this entire Helmet block:
      <Helmet>
        <script type="application/ld+json">
          {JSON.stringify({
            "@context": "https://schema.org",
            "@type": "Article",
            "headline": "Entertainment Chat - Fun Video Chat Platform",
            "description": "Entertain yourself with random video chat. Meet interesting people and have fun conversations.",
            "image": "https://lokalivechat.com/loka-logo.jpeg"
          })}
        </script>
      </Helmet>
      */}

      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <Music className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA Entertainment</h1>
          </Link>
          <Link to="/">
            <Button className="bg-yellow-600 hover:bg-yellow-700">
              <Gamepad2 className="w-4 h-4 mr-2" /> Have Fun
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Entertainment Through <span className="text-yellow-400">Random Chat</span>
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Bored? Looking for fun? Connect with entertaining people from around the world.
            Laugh, share stories, play games, and make every conversation an adventure.
          </p>
        </div>

        {/* Entertainment Options */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">Ways to Entertain Yourself</h2>
          <div className="grid md:grid-cols-2 gap-8">
            {[
              {
                icon: <Laugh className="w-8 h-8" />,
                title: "Fun Conversations",
                desc: "Meet hilarious people who know how to make you laugh. Share jokes and funny stories."
              },
              {
                icon: <Music className="w-8 h-8" />,
                title: "Music Sharing",
                desc: "Share your favorite music with chat partners. Discover new songs together."
              },
              {
                icon: <Gamepad2 className="w-8 h-8" />,
                title: "Game Sessions",
                desc: "Play simple games during your chat. Never run out of things to do."
              },
              {
                icon: <Film className="w-8 h-8" />,
                title: "Movie Discussions",
                desc: "Talk about movies, TV shows, and entertainment with fellow enthusiasts."
              }
            ].map((item, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-8">
                <div className="w-14 h-14 bg-yellow-600 rounded-full flex items-center justify-center mb-6">
                  {item.icon}
                </div>
                <h3 className="text-xl font-bold mb-4">{item.title}</h3>
                <p className="text-gray-300">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default EntertainmentChat;