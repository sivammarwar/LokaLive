import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { Shuffle, Users, Globe, Zap, Target, Sparkles } from "lucide-react";

const RandomChatPage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <Shuffle className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA Random Chat</h1>
          </Link>
          <Link to="/">
            <Button className="bg-purple-600 hover:bg-purple-700">
              <Shuffle className="w-4 h-4 mr-2" /> Random Connect
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Experience the Thrill of <span className="text-purple-400">Random Chat</span>
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Meet completely random strangers from around the world. Every connection is a new adventure,
            a new story, and a new friend waiting to be discovered.
          </p>
        </div>

        {/* Features */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">What Makes Random Chat Exciting?</h2>
          <div className="grid md:grid-cols-2 gap-8">
            {[
              {
                icon: <Sparkles className="w-8 h-8" />,
                title: "The Element of Surprise",
                desc: "Never know who you'll meet next. Each connection brings unexpected conversations and new perspectives."
              },
              {
                icon: <Globe className="w-8 h-8" />,
                title: "Cultural Exchange",
                desc: "Connect with people from different countries, learn about their cultures, and share your own experiences."
              },
              {
                icon: <Target className="w-8 h-8" />,
                title: "No Pressure Conversations",
                desc: "Talk about anything without judgment. Perfect for shy people looking to improve social skills."
              },
              {
                icon: <Users className="w-8 h-8" />,
                title: "Expand Your Network",
                desc: "Make friends from around the world. Some random chats turn into lifelong friendships."
              }
            ].map((item, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-8">
                <div className="w-14 h-14 bg-purple-600 rounded-full flex items-center justify-center mb-6">
                  {item.icon}
                </div>
                <h3 className="text-xl font-bold mb-4">{item.title}</h3>
                <p className="text-gray-300">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {/* CTA */}
        <div className="text-center mb-16">
          <div className="bg-gradient-to-r from-purple-900/30 to-pink-900/30 rounded-2xl p-12">
            <h2 className="text-3xl font-bold mb-6">Ready for Your Next Random Adventure?</h2>
            <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
              Click the button below and meet someone completely random in seconds.
            </p>
            <Link to="/">
              <Button size="lg" className="bg-purple-600 hover:bg-purple-700 text-lg px-8 py-6">
                <Shuffle className="mr-2" /> Connect Randomly Now
              </Button>
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default RandomChatPage;