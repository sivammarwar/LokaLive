import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { Facebook, Instagram, Users, Zap, Globe, Shield } from "lucide-react";

const SocialComparison = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <Users className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA vs Social Media</h1>
          </Link>
          <Link to="/">
            <Button className="bg-purple-600 hover:bg-purple-700">
              Meet New People
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Beyond <span className="text-blue-400">Facebook</span> & <span className="text-pink-400">Instagram</span>
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Tired of only chatting with people you already know? LOKA helps you meet completely new people
            from around the world through random video chat.
          </p>
        </div>

        {/* Comparison */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">How LOKA Differs from Social Media</h2>
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                icon: <Facebook className="w-8 h-8 text-blue-500" />,
                title: "Facebook",
                points: ["Chat with friends", "Known contacts", "Profile required", "Algorithm feeds"]
              },
              {
                icon: <Instagram className="w-8 h-8 text-pink-500" />,
                title: "Instagram",
                points: ["Follow-based", "Visual content", "DMs with followers", "Public profiles"]
              },
              {
                icon: <Users className="w-8 h-8 text-purple-500" />,
                title: "LOKA",
                points: ["Meet strangers", "No profile needed", "Random connections", "Video focus"]
              }
            ].map((platform, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-8">
                <div className="flex items-center justify-center gap-3 mb-6">
                  {platform.icon}
                  <h3 className="text-2xl font-bold">{platform.title}</h3>
                </div>
                <ul className="space-y-3">
                  {platform.points.map((point, idx) => (
                    <li key={idx} className="flex items-center gap-3">
                      <div className="w-2 h-2 bg-purple-500 rounded-full"></div>
                      <span>{point}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>

        {/* Benefits */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">Why Meet New People?</h2>
          <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            <div className="bg-gray-800/30 rounded-xl p-8">
              <h3 className="text-xl font-bold mb-4 flex items-center gap-3">
                <Globe className="w-6 h-6" /> Expand Your Horizons
              </h3>
              <p className="text-gray-300">
                Social media keeps you in your bubble. LOKA helps you break out and meet people
                from different cultures, backgrounds, and perspectives.
              </p>
            </div>
            <div className="bg-gray-800/30 rounded-xl p-8">
              <h3 className="text-xl font-bold mb-4 flex items-center gap-3">
                <Shield className="w-6 h-6" /> Privacy Focused
              </h3>
              <p className="text-gray-300">
                Unlike social media, LOKA doesn't track your activity, build profiles, or show targeted ads.
                Chat anonymously without algorithms watching.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SocialComparison;