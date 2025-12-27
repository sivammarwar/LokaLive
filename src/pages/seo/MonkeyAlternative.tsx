import { Button } from "@/components/ui/button";
import SEOHandler from '@/components/seo/SEOHandler';
import { Link } from "react-router-dom";
import { Smartphone, Download, Globe, Zap, CheckCircle } from "lucide-react";

const MonkeyAlternative = () => {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      {/* ✅ REPLACE Helmet with SEOHandler */}
      <SEOHandler />
      
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-12">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center">
              <Smartphone className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold">LOKA vs Monkey</h1>
          </Link>
          <Link to="/">
            <Button className="bg-purple-600 hover:bg-purple-700">
              Try LOKA Free
            </Button>
          </Link>
        </div>

        <div className="text-center mb-16">
          <h1 className="text-4xl md:text-5xl font-bold mb-6">
            Best <span className="text-orange-400">Monkey App Alternative</span> for 2024
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-3xl mx-auto">
            Tired of downloading apps? LOKA offers all the features of Monkey app but directly in your browser.
            No app store, no downloads, no updates needed.
          </p>
        </div>

        {/* Comparison */}
        <div className="mb-16 bg-gray-800/30 rounded-2xl p-8">
          <h2 className="text-3xl font-bold text-center mb-10">LOKA vs Monkey App</h2>
          <div className="grid md:grid-cols-2 gap-8">
            <div className="text-center p-6">
              <div className="text-2xl font-bold mb-6 flex items-center justify-center gap-2">
                <Smartphone className="w-6 h-6" /> Monkey App
              </div>
              <ul className="space-y-4 text-left">
                <li className="flex items-start gap-3">
                  <div className="text-gray-400 mt-1">•</div>
                  <span>Requires app download</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-gray-400 mt-1">•</div>
                  <span>App store approval needed</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-gray-400 mt-1">•</div>
                  <span>Limited to mobile devices</span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-gray-400 mt-1">•</div>
                  <span>Regular updates required</span>
                </li>
              </ul>
            </div>
            
            <div className="text-center p-6 border-2 border-purple-500 rounded-xl">
              <div className="text-2xl font-bold mb-6 flex items-center justify-center gap-2 text-purple-400">
                <Globe className="w-6 h-6" /> LOKA
              </div>
              <ul className="space-y-4 text-left">
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>No download required</strong></span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Works on all devices</strong></span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>Always up-to-date</strong></span>
                </li>
                <li className="flex items-start gap-3">
                  <div className="text-green-400 mt-1">✓</div>
                  <span><strong>No app store restrictions</strong></span>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* CTA */}
        <div className="text-center">
          <div className="bg-gradient-to-r from-orange-900/20 to-purple-900/20 rounded-2xl p-12">
            <h2 className="text-3xl font-bold mb-6">Try the Web-Based Monkey Alternative</h2>
            <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
              Get all the random chat fun without downloading anything. Works on any device instantly.
            </p>
            <Link to="/">
              <Button size="lg" className="bg-purple-600 hover:bg-purple-700 text-lg px-8 py-6">
                <Zap className="mr-2" /> Start in Browser
              </Button>
            </Link>
            <p className="text-gray-400 mt-6">
              No download • No registration • Instant access
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MonkeyAlternative;