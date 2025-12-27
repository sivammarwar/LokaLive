import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { Video, Shield, Users, Zap, Globe, MessageSquare, CheckCircle } from "lucide-react";

const OmegleAlternative = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      {/* Header */}
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <div className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <Video className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA</h1>
          </div>
          <Link to="/">
            <Button className="bg-purple-600 hover:bg-purple-700">
              Start Chatting Now
            </Button>
          </Link>
        </div>

        {/* Hero Section */}
        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            The Best <span className="text-purple-400">Omegle Alternative</span> in 2024
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Looking for an Omegle alternative? LOKA offers everything Omegle did, plus better features,
            enhanced safety, and a more modern interface. Connect with strangers worldwide instantly.
          </p>
          <div className="flex flex-wrap justify-center gap-4 mb-12">
            <Button size="lg" className="bg-purple-600 hover:bg-purple-700">
              <Zap className="mr-2" /> Start Free Chat
            </Button>
            <Button size="lg" variant="outline" className="border-purple-400 text-purple-400">
              <MessageSquare className="mr-2" /> Learn More
            </Button>
          </div>
        </div>

        {/* Comparison Section */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">
            LOKA vs Omegle: Why Choose LOKA?
          </h2>
          <div className="grid md:grid-cols-2 gap-8">
            <div className="bg-gray-800/50 rounded-xl p-8 border border-gray-700">
              <h3 className="text-2xl font-bold mb-6 flex items-center gap-3">
                <div className="w-10 h-10 bg-red-500 rounded-full flex items-center justify-center">
                  <span className="font-bold">O</span>
                </div>
                Omegle (Discontinued)
              </h3>
              <ul className="space-y-4">
                <li className="flex items-start gap-3">
                  <div className="text-red-400 mt-1">✗</div>
                  <span>No longer available since November 2023</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-red-400 mt-1">✗</div>
                  <span>Limited moderation features</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-red-400 mt-1">✗</div>
                  <span>No gender or country filters</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-red-400 mt-1">✗</div>
                  <span>Basic interface design</span>
                </li>
              </ul>
            </div>

            <div className="bg-gray-800/50 rounded-xl p-8 border border-purple-500 border-2">
              <h3 className="text-2xl font-bold mb-6 flex items-center gap-3">
                <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
                  <Video className="w-6 h-6" />
                </div>
                LOKA (Better Alternative)
              </h3>
              <ul className="space-y-4">
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Active and growing platform</strong></span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Enhanced safety features</strong> and reporting system</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Gender and country filters</strong> for better matching</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Modern interface</strong> with dark mode</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Built-in text chat</strong> alongside video</span>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* Features */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">
            Why LOKA is the Best Omegle Alternative
          </h2>
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center p-6">
              <div className="w-16 h-16 bg-purple-600 rounded-full flex items-center justify-center mx-auto mb-4">
                <Shield className="w-8 h-8" />
              </div>
              <h3 className="text-xl font-bold mb-3">Enhanced Safety</h3>
              <p className="text-gray-300">
                Advanced moderation, reporting system, and user verification for safer conversations.
              </p>
            </div>
            <div className="text-center p-6">
              <div className="w-16 h-16 bg-purple-600 rounded-full flex items-center justify-center mx-auto mb-4">
                <Globe className="w-8 h-8" />
              </div>
              <h3 className="text-xl font-bold mb-3">Global Connections</h3>
              <p className="text-gray-300">
                Meet people from every corner of the world. Country filters to find specific regions.
              </p>
            </div>
            <div className="text-center p-6">
              <div className="w-16 h-16 bg-purple-600 rounded-full flex items-center justify-center mx-auto mb-4">
                <Users className="w-8 h-8" />
              </div>
              <h3 className="text-xl font-bold mb-3">Active Community</h3>
              <p className="text-gray-300">
                Thousands of active users online 24/7. Always find someone to chat with.
              </p>
            </div>
          </div>
        </div>

        {/* How to Use */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">
            How to Use LOKA (It's Easy!)
          </h2>
          <div className="grid md:grid-cols-4 gap-6">
            {[
              { step: "1", title: "Visit LOKA", desc: "Go to loka.lovable.app" },
              { step: "2", title: "Enable Camera", desc: "Allow camera and microphone access" },
              { step: "3", title: "Set Preferences", desc: "Choose gender, country filters" },
              { step: "4", title: "Start Chatting", desc: "Click connect and meet strangers!" }
            ].map((item) => (
              <div key={item.step} className="text-center p-6 bg-gray-800/30 rounded-xl">
                <div className="w-12 h-12 bg-purple-600 rounded-full flex items-center justify-center mx-auto mb-4 text-xl font-bold">
                  {item.step}
                </div>
                <h3 className="text-lg font-bold mb-2">{item.title}</h3>
                <p className="text-gray-400">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {/* FAQ */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">
            Frequently Asked Questions
          </h2>
          <div className="space-y-6 max-w-3xl mx-auto">
            {[
              {
                q: "Is LOKA really free like Omegle was?",
                a: "Yes, LOKA is completely free to use with no hidden charges. No premium subscriptions required."
              },
              {
                q: "Do I need to register or login?",
                a: "No registration or login required! Just visit the site, enable your camera, and start chatting."
              },
              {
                q: "Is LOKA safe to use?",
                a: "LOKA has enhanced safety features including user reporting, moderation, and privacy controls that Omegle didn't have."
              },
              {
                q: "Can I use LOKA on mobile?",
                a: "Yes, LOKA works perfectly on all devices - smartphones, tablets, and computers."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-6">
                <h3 className="text-xl font-bold mb-3">{faq.q}</h3>
                <p className="text-gray-300">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>

        {/* CTA Section */}
        <div className="text-center bg-gradient-to-r from-purple-900/30 to-blue-900/30 rounded-2xl p-12">
          <h2 className="text-3xl font-bold mb-6">
            Ready to Try the Best Omegle Alternative?
          </h2>
          <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
            Join thousands of users who have switched from Omegle to LOKA. Experience better features,
            enhanced safety, and a thriving community.
          </p>
          <Link to="/">
            <Button size="lg" className="bg-purple-600 hover:bg-purple-700 text-lg px-8 py-6">
              <Zap className="mr-2" /> Start Free Video Chat Now
            </Button>
          </Link>
          <p className="text-gray-400 mt-6">
            No registration required • Free forever • Thousands of active users
          </p>
        </div>

        {/* Related Links */}
        <div className="mt-16 text-center">
          <h3 className="text-xl font-bold mb-6">More Random Chat Alternatives</h3>
          <div className="flex flex-wrap justify-center gap-4">
            <Link to="/ometv-alternative" className="text-purple-400 hover:text-purple-300">
              OmeTV Alternative →
            </Link>
            <Link to="/monkey-alternative" className="text-purple-400 hover:text-purple-300">
              Monkey App Alternative →
            </Link>
            <Link to="/live-chat" className="text-purple-400 hover:text-purple-300">
              Live Chat →
            </Link>
            <Link to="/random-chat" className="text-purple-400 hover:text-purple-300">
              Random Chat →
            </Link>
          </div>
        </div>
      </div>

      {/* Footer */}
      <div className="border-t border-gray-800 mt-16 py-8">
        <div className="container mx-auto px-4 text-center text-gray-400">
          <p>© 2025 LOKA - Best Omegle Alternative for Random Video Chat</p>
          <p className="mt-2">
            <Link to="/" className="hover:text-purple-400">Home</Link> • 
            <Link to="/privacy" className="hover:text-purple-400 ml-4">Privacy</Link> • 
            <Link to="/terms" className="hover:text-purple-400 ml-4">Terms</Link> • 
            <Link to="/contact" className="hover:text-purple-400 ml-4">Contact</Link>
          </p>
        </div>
      </div>
    </div>
  );
};

export default OmegleAlternative;