import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { Video, Clock, Globe, Users, MessageSquare, Zap, CheckCircle } from "lucide-react";

const LiveChatPage = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <Video className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA Live Chat</h1>
          </Link>
          <Link to="/">
            <Button className="bg-green-600 hover:bg-green-700">
              <Clock className="w-4 h-4 mr-2" /> Go Live Now
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Experience <span className="text-green-400">Real-Time Live Chat</span> with Strangers
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Connect instantly with people from around the world through live video and text chat.
            No delays, no buffering - just real-time conversations that feel like you're in the same room.
          </p>
          <div className="flex flex-wrap justify-center gap-4 mb-12">
            <Link to="/">
              <Button size="lg" className="bg-green-600 hover:bg-green-700">
                <Zap className="mr-2" /> Start Live Chat
              </Button>
            </Link>
          </div>
        </div>

        {/* Benefits */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">Why Choose LOKA for Live Chat?</h2>
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                icon: <Clock className="w-8 h-8" />,
                title: "Instant Connections",
                desc: "Connect with strangers in under 3 seconds. No waiting rooms, no queues."
              },
              {
                icon: <Globe className="w-8 h-8" />,
                title: "Global Reach",
                desc: "Chat with people from over 150 countries. Experience different cultures in real-time."
              },
              {
                icon: <MessageSquare className="w-8 h-8" />,
                title: "Dual Chat",
                desc: "Video chat with real-time text messaging. Perfect when you want to share links or text."
              }
            ].map((item, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-8 text-center">
                <div className="w-16 h-16 bg-green-600 rounded-full flex items-center justify-center mx-auto mb-6">
                  {item.icon}
                </div>
                <h3 className="text-xl font-bold mb-4">{item.title}</h3>
                <p className="text-gray-300">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Stats */}
        <div className="mb-16 bg-gray-800/30 rounded-2xl p-8">
          <h2 className="text-3xl font-bold text-center mb-10">Live Chat Statistics</h2>
          <div className="grid md:grid-cols-4 gap-6">
            {[
              { number: "10,000+", label: "Daily Active Users" },
              { number: "150+", label: "Countries Represented" },
              { number: "24/7", label: "Live Connections" },
              { number: "<3s", label: "Average Connection Time" }
            ].map((stat, index) => (
              <div key={index} className="text-center p-6">
                <div className="text-4xl font-bold text-green-400 mb-2">{stat.number}</div>
                <div className="text-gray-300">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>

        {/* CTA */}
        <div className="text-center mb-16">
          <div className="bg-gradient-to-r from-green-900/20 to-purple-900/20 rounded-2xl p-12">
            <h2 className="text-3xl font-bold mb-6">Start Your Live Chat Journey Today</h2>
            <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
              Join thousands of users having real conversations right now. No registration, no downloads.
            </p>
            <Link to="/">
              <Button size="lg" className="bg-green-600 hover:bg-green-700 text-lg px-8 py-6">
                <Video className="mr-2" /> Go Live Instantly
              </Button>
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default LiveChatPage;