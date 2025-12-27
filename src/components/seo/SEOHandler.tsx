import { Helmet } from "react-helmet-async";
import { useLocation } from "react-router-dom";

const SEOHandler = () => {
  const location = useLocation();
  const currentPath = location.pathname;

  const pageSEO = {
    // Existing pages...
    "/": {
      title: "LOKA - Free Random Video Chat | Play Games with Strangers",
      description: "Connect instantly with random strangers worldwide. Play chess and multiplayer games with video chat. No registration required.",
      keywords: "omegle alternative, random video chat, chess game online, multiplayer games, play with strangers, live chat",
      canonical: "https://lokalivechat.com"
    },

    "/omegle-alternative": {
      title: "Best Omegle Alternative - Free Random Video Chat | LOKA",
      description: "Looking for Omegle alternatives? LOKA offers free random video chat without registration. Better features, safer environment. Try now!",
      keywords: "omegle alternative, omegle replacement, random video chat, free chat like omegle, omegle 2024",
      canonical: "https://lokalivechat.com/omegle-alternative"
    },

    "/ometv-alternative": {
      title: "OmeTV Alternative - Better Random Video Chat Platform | LOKA",
      description: "Best OmeTV alternative for random video chat. Free, no registration, gender filters, and better user experience than OmeTV.",
      keywords: "ometv alternative, random chat app, video chat alternative, free chat, ometv replacement",
      canonical: "https://lokalivechat.com/ometv-alternative"
    },

    "/live-chat": {
      title: "Live Chat Online - Free Real-Time Video Chat | LOKA",
      description: "Experience live chat with real people worldwide. Instant connections, webcam chat, and text messaging. No downloads required.",
      keywords: "live chat, live video chat, online chat, webcam chat, real-time chat",
      canonical: "https://lokalivechat.com/live-chat"
    },

    "/random-chat": {
      title: "Random Chat - Meet Strangers Instantly | Free Video Chat",
      description: "Random chat with strangers from around the world. Free video and text chat with instant connections. Make new friends today!",
      keywords: "random chat, stranger chat, meet new people, random video chat, chat with strangers",
      canonical: "https://lokalivechat.com/random-chat"
    },

    "/no-login-chat": {
      title: "Chat Without Login - Free Anonymous Video Chat | LOKA",
      description: "Chat instantly without any registration or login. 100% anonymous random video chat. No email, no signup, just click and chat.",
      keywords: "chat without login, no registration chat, anonymous chat, free chat no signup, instant chat",
      canonical: "https://lokalivechat.com/no-login-chat"
    },

    "/entertainment-chat": {
      title: "Entertainment Chat - Fun Video Chat Platform | LOKA",
      description: "Entertain yourself with random video chat. Meet interesting people, have fun conversations, and enjoy live entertainment.",
      keywords: "entertainment chat, fun chat, video entertainment, social entertainment, online fun",
      canonical: "https://lokalivechat.com/entertainment-chat"
    },

    "/monkey-alternative": {
      title: "Monkey App Alternative - Better Random Video Chat | LOKA",
      description: "Looking for Monkey app alternatives? LOKA offers free random video chat with better features, no app download required.",
      keywords: "monkey app alternative, monkey alternative, random video chat app, video chat like monkey",
      canonical: "https://lokalivechat.com/monkey-alternative"
    },

    "/chat-apps-comparison": {
      title: "Facebook & Instagram Chat Alternatives | Random Video Chat",
      description: "Compare LOKA with Facebook and Instagram chat features. Better for meeting strangers and random video conversations.",
      keywords: "facebook chat alternative, instagram alternative, social media chat, random video chat, meet new people",
      canonical: "https://lokalivechat.com/chat-apps-comparison"
    },

    // NEW GAMING PAGES:
    "/multiplayer-games": {
      title: "Multiplayer Games Online | Play with Real People | LOKA",
      description: "Play multiplayer games online with real people. Connect via video chat and enjoy games like chess, checkers, and more with strangers.",
      keywords: "multiplayer games, online games, play with real people, real-time games, video chat games, online gaming",
      canonical: "https://lokalivechat.com/multiplayer-games"
    },
    
    "/chess-game": {
      title: "Play Chess Online with Video Chat | Real-Time Multiplayer Chess",
      description: "Play chess online with strangers via video chat. Real-time multiplayer chess with voice and video. No registration, free to play.",
      keywords: "chess online, play chess, chess with video chat, multiplayer chess, online chess game, chess with strangers",
      canonical: "https://lokalivechat.com/chess-game"
    },
    
    "/online-multiplayer-game": {
      title: "Online Multiplayer Games | Play with Real Users | LOKA",
      description: "Play online multiplayer games with real users worldwide. Video chat while gaming makes it more social and exciting.",
      keywords: "online multiplayer game, play with real users, multiplayer online, real-time gaming, social games",
      canonical: "https://lokalivechat.com/online-multiplayer-game"
    },
    
    "/play-with-real-user": {
      title: "Play Games with Real Users | Human Opponents Online",
      description: "Tired of playing against bots? Play games with real human users. Live video chat makes every match unique and exciting.",
      keywords: "play with real user, human opponents, real people games, not bots, live opponents",
      canonical: "https://lokalivechat.com/play-with-real-user"
    },
    
    "/real-time-game": {
      title: "Real-Time Games Online | Live Multiplayer Gaming",
      description: "Experience real-time multiplayer gaming with instant responses. No lag, just smooth gameplay with live opponents.",
      keywords: "real-time game, live multiplayer, instant gaming, no delay games, real-time online",
      canonical: "https://lokalivechat.com/real-time-game"
    },
    
    "/play-chess-with-video-chat": {
      title: "Play Chess with Video Chat | See Your Opponent Live",
      description: "Unique chess experience with live video chat. See your opponent's reactions, discuss strategies, and make new chess friends.",
      keywords: "play chess with video chat, chess video call, see opponent, face-to-face chess, social chess",
      canonical: "https://lokalivechat.com/play-chess-with-video-chat"
    }
  };

  const seoData = pageSEO[currentPath as keyof typeof pageSEO] || pageSEO["/"];

  return (
    <Helmet>
      <title>{seoData.title}</title>
      <meta name="description" content={seoData.description} />
      <meta name="keywords" content={seoData.keywords} />
      <link rel="canonical" href={seoData.canonical} />
      
      {/* Open Graph */}
      <meta property="og:title" content={seoData.title} />
      <meta property="og:description" content={seoData.description} />
      <meta property="og:url" content={seoData.canonical} />
      <meta property="og:image" content="https://lokalivechat.com/loka-logo.jpeg" />
      <meta property="og:type" content="website" />
      
      {/* Twitter */}
      <meta name="twitter:title" content={seoData.title} />
      <meta name="twitter:description" content={seoData.description} />
      <meta name="twitter:image" content="https://lokalivechat.com/loka-logo.jpeg" />
      <meta name="twitter:card" content="summary_large_image" />
      
      {/* Additional SEO */}
      <meta name="robots" content="index, follow, max-image-preview:large" />
      <meta name="googlebot" content="index, follow" />
      <meta name="bingbot" content="index, follow" />
    </Helmet>
  );
};

export default SEOHandler;