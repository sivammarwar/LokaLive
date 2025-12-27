import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { UserX, Shield, Zap, Lock, Clock, Globe } from "lucide-react";

const NoLoginChat = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <UserX className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA - No Login Chat</h1>
          </Link>
          <Link to="/">
            <Button className="bg-purple-600 hover:bg-purple-700">
              <Zap className="w-4 h-4 mr-2" /> Start Instantly
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Chat <span className="text-red-400">Without Login</span> - 100% Anonymous
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            No email, no password, no registration. Just click and start chatting instantly.
            Your privacy is protected - we don't store personal information.
          </p>
        </div>

        {/* Benefits */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">Why No-Login Chat is Better</h2>
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                icon: <Lock className="w-8 h-8" />,
                title: "Complete Privacy",
                desc: "No personal data collection. Your conversations remain private and anonymous."
              },
              {
                icon: <Clock className="w-8 h-8" />,
                title: "Instant Access",
                desc: "Start chatting in seconds. No registration forms, no verification emails."
              },
              {
                icon: <Shield className="w-8 h-8" />,
                title: "No Tracking",
                desc: "We don't track your activity or save chat history. Truly anonymous experience."
              }
            ].map((item, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-8 text-center">
                <div className="w-16 h-16 bg-red-600 rounded-full flex items-center justify-center mx-auto mb-6">
                  {item.icon}
                </div>
                <h3 className="text-xl font-bold mb-4">{item.title}</h3>
                <p className="text-gray-300">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {/* How it works */}
        <div className="mb-16 bg-gray-800/30 rounded-2xl p-8">
          <h2 className="text-3xl font-bold text-center mb-10">How No-Login Chat Works</h2>
          <div className="grid md:grid-cols-4 gap-6">
            {[
              { step: "1", title: "Visit Site", desc: "Go to LOKA" },
              { step: "2", title: "Allow Camera", desc: "Enable camera access" },
              { step: "3", title: "Set Preferences", desc: "Optional filters" },
              { step: "4", title: "Chat Now", desc: "Start conversations" }
            ].map((item) => (
              <div key={item.step} className="text-center p-6">
                <div className="w-12 h-12 bg-red-600 rounded-full flex items-center justify-center mx-auto mb-4 text-xl font-bold">
                  {item.step}
                </div>
                <h3 className="text-lg font-bold mb-2">{item.title}</h3>
                <p className="text-gray-400">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default NoLoginChat;