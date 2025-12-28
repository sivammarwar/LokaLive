import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useUserStore } from '@/lib/userStore';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Users, Video, Shield, Mail, Key, Crown, Lock, Globe, UserPlus, Zap, Grid, Sparkles } from 'lucide-react';

type LoginStep = 'EMAIL_INPUT' | 'OTP_VERIFICATION' | 'DISPLAY_NAME_INPUT';

export default function Login() {
  const [email, setEmail] = useState('');
  const [otp, setOtp] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [step, setStep] = useState<LoginStep>('EMAIL_INPUT');
  const [isLoading, setIsLoading] = useState(false);
  const [verifiedUser, setVerifiedUser] = useState<any>(null);
  
  const navigate = useNavigate();
  const setUser = useUserStore((state) => state.setUser);
  
  const generateFingerprint = async () => {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.textBaseline = 'top';
      ctx.font = '14px Arial';
      ctx.fillText('fingerprint', 2, 2);
    }
    const canvasData = canvas.toDataURL();
    
    const userAgent = navigator.userAgent;
    const language = navigator.language;
    const platform = navigator.platform;
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    
    const raw = `${canvasData}${userAgent}${language}${platform}${timezone}`;
    const encoder = new TextEncoder();
    const data = encoder.encode(raw);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  };

  const handleSendOtp = async () => {
    if (!email.trim()) {
      toast.error('Please enter your email.');
      return;
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email.trim())) {
      toast.error('Please enter a valid email address.');
      return;
    }

    setIsLoading(true);
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        options: {
          shouldCreateUser: true,
          emailRedirectTo: undefined,
        },
      });

      if (error) throw error;
      
      toast.success('Check your email! 6-digit code expires in 60 seconds.');
      setStep('OTP_VERIFICATION');
    } catch (error: any) {
      console.error('OTP send error:', error);
      toast.error(error.message || 'Could not send OTP. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (!otp.trim() || otp.trim().length !== 6) {
      toast.error('Please enter the complete 6-digit code.');
      return;
    }
    
    setIsLoading(true);

    try {
      const { data, error } = await supabase.auth.verifyOtp({
        email: email.trim(),
        token: otp.trim(),
        type: 'email',
      });

      if (error || !data.user) {
        throw new Error(error?.message || 'Verification failed');
      }

      setVerifiedUser(data.user);
      toast.success('Code verified! Choose your display name.');
      setStep('DISPLAY_NAME_INPUT');
    } catch (error: any) {
      console.error('OTP verification error:', error);
      
      let errorMessage = 'Invalid or expired code. Please try again.';
      
      if (error.message) {
        if (error.message.includes('expired')) {
          errorMessage = 'Code expired. Please request a new one.';
        } else if (error.message.includes('Invalid')) {
          errorMessage = 'Invalid code. Please check and try again.';
        } else {
          errorMessage = error.message;
        }
      }
      
      toast.error(errorMessage);
      setOtp('');
    } finally {
      setIsLoading(false);
    }
  };

  const handleCompleteLogin = async () => {
    if (!displayName.trim()) {
      toast.error('Please enter a display name.');
      return;
    }

    if (displayName.trim().length < 2) {
      toast.error('Display name must be at least 2 characters.');
      return;
    }

    if (!verifiedUser) {
      toast.error('Session expired. Please try again.');
      setStep('EMAIL_INPUT');
      return;
    }

    setIsLoading(true);

    try {
      const supabaseUser = verifiedUser;
      const sessionToken = crypto.randomUUID();
      const fingerprint = await generateFingerprint();

      const { data: userProfiles, error: profileError } = await supabase
        .from('users')
        .select('id, display_name, email, is_permanently_banned, banned_until, health_tokens, gender')
        .eq('id', supabaseUser.id);

      if (profileError) {
        console.error('Profile fetch error:', profileError);
      }

      let userProfile = userProfiles && userProfiles.length > 0 ? userProfiles[0] : null;

      if (userProfile) {
        if (userProfile.is_permanently_banned) {
          await supabase.auth.signOut();
          toast.error('Your account has been permanently suspended.');
          setIsLoading(false);
          return;
        }

        if (userProfile.banned_until && new Date(userProfile.banned_until) > new Date()) {
          await supabase.auth.signOut();
          const banDate = new Date(userProfile.banned_until);
          toast.error(`Your account is suspended until ${banDate.toLocaleDateString()}`);
          setIsLoading(false);
          return;
        }

        const { error: updateError } = await supabase
          .from('users')
          .update({
            display_name: displayName.trim(),
            session_token: sessionToken,
            browser_fingerprint: fingerprint,
            updated_at: new Date().toISOString(),
          })
          .eq('id', userProfile.id);

        if (updateError) {
          console.error('Update error:', updateError);
        }

        setUser(
          userProfile.id,
          displayName.trim(),
          sessionToken,
          userProfile.health_tokens || 5
        );
        
        toast.success(`Welcome back, ${displayName.trim()}!`);
        navigate('/create-room');
      } else {
        console.log('Creating new user profile...');
        
        const { data: newProfile, error: insertError } = await supabase
          .from('users')
          .insert({
            id: supabaseUser.id,
            email: supabaseUser.email,
            display_name: displayName.trim(),
            session_token: sessionToken,
            browser_fingerprint: fingerprint,
            health_tokens: 5,
          })
          .select('id, display_name, email, health_tokens')
          .single();

        if (insertError) {
          console.error('Insert error:', insertError);
          await new Promise(resolve => setTimeout(resolve, 500));
          
          const { data: retryProfile } = await supabase
            .from('users')
            .select('id, display_name, email, health_tokens')
            .eq('id', supabaseUser.id)
            .single();

          if (retryProfile) {
            setUser(
              retryProfile.id,
              displayName.trim(),
              sessionToken,
              retryProfile.health_tokens || 5
            );
            toast.success(`Welcome to Loka, ${displayName.trim()}!`);
            navigate('/create-room');
          } else {
            throw new Error('Could not create user profile. Please try again.');
          }
        } else {
          setUser(
            newProfile.id,
            displayName.trim(),
            sessionToken,
            newProfile.health_tokens || 5
          );
          toast.success(`Welcome to Loka, ${displayName.trim()}!`);
          navigate('/create-room');
        }
      }
    } catch (error: any) {
      console.error('Login completion error:', error);
      
      let errorMessage = 'Could not complete login. Please try again.';
      
      if (error.message) {
        errorMessage = error.message;
      }
      
      toast.error(errorMessage);
      setStep('EMAIL_INPUT');
      setOtp('');
      setDisplayName('');
    } finally {
      setIsLoading(false);
    }
  };

  const features = [
    { 
      icon: Users, 
      title: '2 & 4 Person Rooms', 
      desc: 'Random video chat with multiple people',
      color: 'from-blue-500 to-cyan-500'
    },
    { 
      icon: Lock, 
      title: 'Private Rooms', 
      desc: 'Custom codes & screen sharing',
      color: 'from-purple-500 to-pink-500'
    },
    { 
      icon: Grid, 
      title: 'Chess Battles', 
      desc: 'Play chess with diamond betting',
      color: 'from-green-500 to-emerald-500'
    },
    { 
      icon: Crown, 
      title: 'Premium Plus', 
      desc: 'Priority matching & live counters',
      color: 'from-yellow-500 to-orange-500'
    },
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-blue-900 to-purple-900 text-white overflow-auto">
      {/* Animated Background */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-0 left-1/4 w-96 h-96 bg-blue-500/20 rounded-full blur-[150px] animate-pulse" />
        <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-purple-500/20 rounded-full blur-[150px] animate-pulse" style={{ animationDelay: '1s' }} />
        <div className="absolute top-1/2 left-1/2 w-96 h-96 bg-pink-500/20 rounded-full blur-[150px] animate-pulse" style={{ animationDelay: '2s' }} />
      </div>

      {/* Hero Section */}
      <div className="relative z-10 container mx-auto px-4 py-8">
        {/* Header */}
        <div className="flex items-center justify-between mb-12">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-purple-600 rounded-2xl flex items-center justify-center transform hover:scale-110 transition-transform">
              <Video className="w-7 h-7" />
            </div>
            <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
              Loka
            </h1>
          </div>
          <div className="flex gap-2">
            <span className="px-4 py-2 bg-white/10 backdrop-blur-lg rounded-full text-sm font-medium border border-white/20">
              <Zap className="w-4 h-4 inline mr-1" />
              Next-Gen Chat
            </span>
          </div>
        </div>

        <div className="grid lg:grid-cols-2 gap-12 items-center max-w-7xl mx-auto">
          {/* Left Side - Hero Content */}
          <div className="space-y-8 order-2 lg:order-1">
            <div className="space-y-4">
              <div className="inline-block px-4 py-2 bg-gradient-to-r from-blue-500/20 to-purple-500/20 rounded-full border border-blue-400/30 backdrop-blur-sm">
                <span className="text-sm font-semibold bg-gradient-to-r from-blue-300 to-purple-300 bg-clip-text text-transparent">
                  ✨ Better than Others
                </span>
              </div>
              
              <h2 className="text-5xl md:text-6xl font-bold leading-tight">
                Random Video Chat
                <span className="block bg-gradient-to-r from-blue-400 via-purple-400 to-pink-400 bg-clip-text text-transparent">
                  Reimagined
                </span>
              </h2>
              
              <p className="text-xl text-gray-300 leading-relaxed">
                Meet new people worldwide with advanced features, premium matchmaking, and seamless video quality. Join millions in the next generation of anonymous chat.
              </p>
            </div>

            {/* Feature Cards */}
            <div className="grid grid-cols-2 gap-4">
              {features.map((feature, idx) => (
                <div
                  key={idx}
                  className="group p-5 rounded-2xl bg-white/5 backdrop-blur-sm border border-white/10 hover:border-white/30 transition-all duration-300 hover:transform hover:scale-105"
                >
                  <div className={`w-12 h-12 rounded-xl bg-gradient-to-br ${feature.color} flex items-center justify-center mb-3 group-hover:scale-110 transition-transform`}>
                    <feature.icon className="w-6 h-6" />
                  </div>
                  <h3 className="font-bold text-sm mb-1">{feature.title}</h3>
                  <p className="text-xs text-gray-400">{feature.desc}</p>
                </div>
              ))}
            </div>

            {/* Stats */}
            <div className="flex gap-8 pt-4">
              <div>
                <div className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-purple-400 text-yellow-400 bg-clip-text text-transparent">
                 🫵
                </div>
                <div className="text-sm text-gray-400">Active Users</div>
              </div>
              <div>
                <div className="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
                  coming soon...
                </div>
                <div className="text-sm text-gray-400">User Rating</div>
              </div>
              <div>
                <div className="text-3xl font-bold bg-gradient-to-r from-pink-400 to-red-400 bg-clip-text text-transparent">
                  24/7
                </div>
                <div className="text-sm text-gray-400">Live Support</div>
              </div>
            </div>
          </div>

          {/* Right Side - Login Form */}
          <div className="order-1 lg:order-2">
            <div className="relative">
              {/* Glow effect */}
              <div className="absolute -inset-1 bg-gradient-to-r from-blue-500 via-purple-500 to-pink-500 rounded-3xl blur-xl opacity-50 animate-pulse" />
              
              {/* Form Card */}
              <div className="relative bg-gray-900/90 backdrop-blur-xl rounded-3xl p-8 border border-white/10 shadow-2xl">
                <div className="text-center mb-8">
                  <h3 className="text-2xl font-bold mb-2">Get Started</h3>
                  <p className="text-gray-400">Join the conversation in seconds</p>
                </div>

                {step === 'EMAIL_INPUT' && (
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium mb-2">Email Address</label>
                      <div className="relative">
                        <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                        <input
                          type="email"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          onKeyDown={(e) => e.key === 'Enter' && handleSendOtp()}
                          placeholder="you@example.com"
                          className="w-full pl-12 pr-4 py-4 bg-white/5 border border-white/10 rounded-2xl focus:border-blue-500 focus:outline-none transition-colors text-white placeholder-gray-500"
                          disabled={isLoading}
                        />
                      </div>
                    </div>

                    <button
                      onClick={handleSendOtp}
                      disabled={isLoading || !email}
                      className="w-full py-4 bg-gradient-to-r from-blue-500 to-purple-600 hover:from-blue-600 hover:to-purple-700 rounded-2xl font-semibold transition-all transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed shadow-lg"
                    >
                      {isLoading ? (
                        <div className="flex items-center justify-center gap-2">
                          <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                          Sending Code...
                        </div>
                      ) : (
                        <div className="flex items-center justify-center gap-2">
                          <Mail className="w-5 h-5" />
                          Continue with Email
                        </div>
                      )}
                    </button>
                  </div>
                )}

                {step === 'OTP_VERIFICATION' && (
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium mb-2">Enter 6-Digit Code</label>
                      <div className="relative">
                        <Key className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                        <input
                          type="text"
                          value={otp}
                          onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
                          onKeyDown={(e) => e.key === 'Enter' && handleVerifyOtp()}
                          placeholder="000000"
                          maxLength={6}
                          className="w-full pl-12 pr-4 py-4 bg-white/5 border border-white/10 rounded-2xl text-center text-3xl font-mono tracking-[0.5em] focus:border-blue-500 focus:outline-none text-white"
                          disabled={isLoading}
                        />
                      </div>
                      <p className="text-xs text-gray-400 mt-2 text-center">
                        Sent to <strong>{email}</strong>
                        <button 
                          onClick={() => {
                            setStep('EMAIL_INPUT');
                            setOtp('');
                          }}
                          className="ml-2 text-blue-400 hover:underline"
                          disabled={isLoading}
                        >
                          Change email
                        </button>
                      </p>
                    </div>

                    <button
                      onClick={handleVerifyOtp}
                      disabled={isLoading || otp.length !== 6}
                      className="w-full py-4 bg-gradient-to-r from-blue-500 to-purple-600 hover:from-blue-600 hover:to-purple-700 rounded-2xl font-semibold transition-all transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      {isLoading ? 'Verifying...' : 'Verify Code'}
                    </button>

                    <button
                      onClick={handleSendOtp}
                      disabled={isLoading}
                      className="w-full text-sm text-gray-400 hover:text-white transition-colors"
                    >
                      Didn't receive code? Resend
                    </button>
                  </div>
                )}

                {step === 'DISPLAY_NAME_INPUT' && (
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium mb-2">Choose Display Name</label>
                      <div className="relative">
                        <UserPlus className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                        <input
                          type="text"
                          value={displayName}
                          onChange={(e) => setDisplayName(e.target.value)}
                          onKeyDown={(e) => e.key === 'Enter' && handleCompleteLogin()}
                          placeholder="Enter your name"
                          maxLength={30}
                          className="w-full pl-12 pr-4 py-4 bg-white/5 border border-white/10 rounded-2xl focus:border-blue-500 focus:outline-none text-white placeholder-gray-500"
                          disabled={isLoading}
                        />
                      </div>
                    </div>

                    <button
                      onClick={handleCompleteLogin}
                      disabled={isLoading || !displayName}
                      className="w-full py-4 bg-gradient-to-r from-blue-500 to-purple-600 hover:from-blue-600 hover:to-purple-700 rounded-2xl font-semibold transition-all transform hover:scale-105 disabled:opacity-50"
                    >
                      {isLoading ? 'Creating Account...' : 'Start Chatting'}
                    </button>
                  </div>
                )}

                <div className="mt-6 flex items-center justify-center gap-2 text-xs text-gray-400">
                  <Shield className="w-4 h-4" />
                  <span>Your data is encrypted and secure</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Features Section */}
        <div className="mt-24 space-y-12">
          <div className="text-center space-y-4">
            <h3 className="text-4xl font-bold">Why Choose Loka?</h3>
            <p className="text-gray-400 text-lg max-w-2xl mx-auto">
              Experience the most advanced random video chat platform with features designed for modern connections
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="p-8 rounded-3xl bg-gradient-to-br from-blue-500/10 to-cyan-500/10 border border-blue-500/20 backdrop-blur-sm hover:transform hover:scale-105 transition-all duration-300">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-cyan-500 rounded-2xl flex items-center justify-center mb-6">
                <Globe className="w-8 h-8" />
              </div>
              <h4 className="text-xl font-bold mb-3">Public Rooms</h4>
              <p className="text-gray-400">Join 2 or 4-person public rooms with intelligent gender-based matching</p>
            </div>

            <div className="p-8 rounded-3xl bg-gradient-to-br from-purple-500/10 to-pink-500/10 border border-purple-500/20 backdrop-blur-sm hover:transform hover:scale-105 transition-all duration-300">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-pink-500 rounded-2xl flex items-center justify-center mb-6">
                <Lock className="w-8 h-8" />
              </div>
              <h4 className="text-xl font-bold mb-3">Private Rooms</h4>
              <p className="text-gray-400">Create private rooms with shareable codes plus screen sharing support</p>
            </div>

            <div className="p-8 rounded-3xl bg-gradient-to-br from-yellow-500/10 to-orange-500/10 border border-yellow-500/20 backdrop-blur-sm hover:transform hover:scale-105 transition-all duration-300">
              <div className="w-16 h-16 bg-gradient-to-br from-yellow-500 to-orange-500 rounded-2xl flex items-center justify-center mb-6">
                <Crown className="w-8 h-8" />
              </div>
              <h4 className="text-xl font-bold mb-3">Premium Features</h4>
              <p className="text-gray-400">See active users, priority matching, enhanced reporting & exclusive perks</p>
            </div>
          </div>

          {/* Chess Feature Section */}
          <div className="mt-16 relative">
            <div className="absolute inset-0 bg-gradient-to-r from-green-500/10 via-emerald-500/10 to-teal-500/10 rounded-3xl blur-3xl" />
            <div className="relative p-8 md:p-12 rounded-3xl bg-gradient-to-br from-green-500/10 to-emerald-500/10 border border-green-500/20 backdrop-blur-sm">
              <div className="grid md:grid-cols-2 gap-8 items-center">
                <div>
                  <div className="inline-block px-4 py-2 bg-gradient-to-r from-green-500/20 to-emerald-500/20 rounded-full border border-green-400/30 backdrop-blur-sm mb-4">
                    <span className="text-sm font-semibold bg-gradient-to-r from-green-300 to-emerald-300 bg-clip-text text-transparent">
                      ♟️ New Feature
                    </span>
                  </div>
                  <h3 className="text-4xl font-bold mb-4">Play Chess with Strangers</h3>
                  <p className="text-gray-300 text-lg mb-6">
                    Challenge your video chat partner to a game of chess. Bet diamonds and win big while having fun!
                  </p>
                  <div className="space-y-3">
                    <div className="flex items-start gap-3">
                      <div className="w-6 h-6 rounded-full bg-green-500/20 flex items-center justify-center flex-shrink-0 mt-1">
                        <div className="w-2 h-2 rounded-full bg-green-400" />
                      </div>
                      <div>
                        <h5 className="font-semibold mb-1">Real-time Chess</h5>
                        <p className="text-sm text-gray-400">Play chess with your video chat partner in real-time</p>
                      </div>
                    </div>
                    <div className="flex items-start gap-3">
                      <div className="w-6 h-6 rounded-full bg-green-500/20 flex items-center justify-center flex-shrink-0 mt-1">
                        <div className="w-2 h-2 rounded-full bg-green-400" />
                      </div>
                      <div>
                        <h5 className="font-semibold mb-1">Diamond Betting</h5>
                        <p className="text-sm text-gray-400">Bet 10-1000 diamonds per game and win double or get refunded on draw</p>
                      </div>
                    </div>
                    <div className="flex items-start gap-3">
                      <div className="w-6 h-6 rounded-full bg-green-500/20 flex items-center justify-center flex-shrink-0 mt-1">
                        <div className="w-2 h-2 rounded-full bg-green-400" />
                      </div>
                      <div>
                        <h5 className="font-semibold mb-1">Seamless Return</h5>
                        <p className="text-sm text-gray-400">After the game, return to video chat in a private 2-person room</p>
                      </div>
                    </div>
                  </div>
                </div>
                <div className="relative">
                  <div className="aspect-square rounded-2xl bg-gradient-to-br from-green-900/50 to-emerald-900/50 border border-green-500/30 p-8 backdrop-blur-sm">
                    {/* Chess Board Visual */}
                    <div className="grid grid-cols-8 gap-0 w-full h-full">
                      {Array.from({ length: 64 }).map((_, i) => {
                        const row = Math.floor(i / 8);
                        const col = i % 8;
                        const isLight = (row + col) % 2 === 0;
                        return (
                          <div
                            key={i}
                            className={`aspect-square ${
                              isLight ? 'bg-amber-200/20' : 'bg-green-900/40'
                            } flex items-center justify-center text-2xl`}
                          >
                            {i === 0 && '♜'}
                            {i === 4 && '♚'}
                            {i === 7 && '♜'}
                            {i === 27 && '♟'}
                            {i === 28 && '♟'}
                            {i === 35 && '♟'}
                            {i === 36 && '♟'}
                            {i === 56 && '♖'}
                            {i === 60 && '♔'}
                            {i === 63 && '♖'}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                  <div className="absolute -bottom-4 -right-4 bg-gradient-to-br from-yellow-500 to-orange-500 rounded-2xl px-6 py-3 shadow-2xl">
                    <div className="flex items-center gap-2 text-sm font-bold">
                      <Sparkles className="w-5 h-5" />
                      <span>Win 2x Diamonds!</span>
                    </div>
                  </div>
                  </div>
              </div>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-24 pt-8 border-t border-white/10 text-center text-sm text-gray-400">
          <p>By continuing, you agree to maintain a safe and respectful community</p>
        </div>
      </div>
    </div>
  );
}