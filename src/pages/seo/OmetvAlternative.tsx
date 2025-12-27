import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { Video, Shield, Filter, Globe, Zap, Users, CheckCircle, BarChart } from "lucide-react";

const OmetvAlternative = () => {
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
            <h1 className="text-2xl font-bold">LOKA</h1>
          </Link>
          <Link to="/">
            <Button className="bg-purple-600 hover:bg-purple-700">
              Start Free Chat
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Better Than <span className="text-blue-400">OmeTV</span>? Why LOKA is the Superior Alternative
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Tired of OmeTV's limitations? LOKA offers a superior random video chat experience with better features,
            enhanced safety, and no annoying ads interrupting your conversations.
          </p>
          <div className="flex flex-wrap justify-center gap-4 mb-12">
            <Link to="/">
              <Button size="lg" className="bg-purple-600 hover:bg-purple-700">
                <Zap className="mr-2" /> Try LOKA Free
              </Button>
            </Link>
            <Button size="lg" variant="outline" className="border-blue-400 text-blue-400">
              <BarChart className="mr-2" /> See Comparison
            </Button>
          </div>
        </div>

        {/* Comparison Table */}
        <div className="mb-16 bg-gray-800/30 rounded-2xl p-8">
          <h2 className="text-3xl font-bold text-center mb-10">LOKA vs OmeTV: Feature Comparison</h2>
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead>
                <tr className="border-b border-gray-700">
                  <th className="pb-4 text-xl">Feature</th>
                  <th className="pb-4 text-xl text-center">OmeTV</th>
                  <th className="pb-4 text-xl text-center text-purple-400">LOKA</th>
                </tr>
              </thead>
              <tbody>
                {[
                  ["Free to Use", "✓", "✓"],
                  ["No Registration Required", "✓", "✓"],
                  ["Gender Filters", "Premium Only", "✓ Free"],
                  ["Country Filters", "Limited", "✓ Full Access"],
                  ["Built-in Text Chat", "✓", "✓ Enhanced"],
                  ["User Reporting", "Basic", "Advanced System"],
                  ["Ad Experience", "Intrusive Ads", "Better Ad Placement"],
                  ["Mobile Friendly", "✓", "✓ Optimized"],
                  ["Video Quality", "Variable", "HD Preferred"],
                  ["Community Size", "Large", "Growing Fast"]
                ].map(([feature, ometv, loka], index) => (
                  <tr key={index} className="border-b border-gray-700/50 hover:bg-gray-800/50">
                    <td className="py-4 font-medium">{feature}</td>
                    <td className="py-4 text-center">{ometv}</td>
                    <td className="py-4 text-center text-purple-300 font-semibold">{loka}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Why Choose LOKA */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">Why Users Are Switching from OmeTV to LOKA</h2>
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                icon: <Filter className="w-8 h-8" />,
                title: "Better Filters",
                desc: "Advanced gender and country filters available for free. Find exactly who you want to chat with."
              },
              {
                icon: <Shield className="w-8 h-8" />,
                title: "Enhanced Safety",
                desc: "Improved moderation system and instant reporting. Safer environment than OmeTV."
              },
              {
                icon: <Globe className="w-8 h-8" />,
                title: "Global Community",
                desc: "Connect with people from every country. More diverse conversations than OmeTV."
              }
            ].map((item, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-8 text-center">
                <div className="w-16 h-16 bg-purple-600 rounded-full flex items-center justify-center mx-auto mb-6">
                  {item.icon}
                </div>
                <h3 className="text-xl font-bold mb-4">{item.title}</h3>
                <p className="text-gray-300">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>

        {/* CTA */}
        <div className="text-center bg-gradient-to-r from-blue-900/20 to-purple-900/20 rounded-2xl p-12 mb-16">
          <h2 className="text-3xl font-bold mb-6">Ready for a Better OmeTV Experience?</h2>
          <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
            Join thousands who have made the switch. Experience random video chat without OmeTV's limitations.
          </p>
          <Link to="/">
            <Button size="lg" className="bg-purple-600 hover:bg-purple-700 text-lg px-8 py-6">
              <Users className="mr-2" /> Start Chatting on LOKA
            </Button>
          </Link>
        </div>

        {/* FAQ */}
        <div className="mb-16">
          <h2 className="text-3xl font-bold text-center mb-12">OmeTV Users Frequently Ask</h2>
          <div className="grid md:grid-cols-2 gap-6 max-w-4xl mx-auto">
            {[
              {
                q: "Is LOKA really better than OmeTV?",
                a: "Yes! LOKA offers better filters, enhanced safety features, and a more user-friendly interface without intrusive ads."
              },
              {
                q: "Do I need the OmeTV app?",
                a: "No! LOKA works directly in your browser - no app download required. Works on all devices instantly."
              },
              {
                q: "Are there country restrictions?",
                a: "LOKA is available worldwide with no country restrictions. Unlike OmeTV, we don't block any regions."
              },
              {
                q: "Is it really free?",
                a: "100% free. No premium tiers for basic features. All filters and features are available to everyone."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-gray-800/30 rounded-xl p-6">
                <h3 className="text-xl font-bold mb-3">{faq.q}</h3>
                <p className="text-gray-300">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Related Links */}
        <div className="text-center">
          <h3 className="text-xl font-bold mb-6">Explore More Alternatives</h3>
          <div className="flex flex-wrap justify-center gap-6">
            <Link to="/omegle-alternative" className="text-blue-400 hover:text-blue-300">
              Omegle Alternative →
            </Link>
            <Link to="/monkey-alternative" className="text-blue-400 hover:text-blue-300">
              Monkey Alternative →
            </Link>
            <Link to="/live-chat" className="text-blue-400 hover:text-blue-300">
              Live Chat →
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OmetvAlternative;