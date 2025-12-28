import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Logo } from '@/components/Logo';
import { useUserStore } from '@/lib/userStore';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Users, Video, Shield, Mail, Key } from 'lucide-react';

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

  const handleSendOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) {
      toast.error('Please enter your email.');
      return;
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email.trim())) {
      toast.error('Please enter a valid email address.');
      return;
    }

    setIsLoading(true);
    try {
      // Use signInWithOtp which sends OTP instead of magic link
      const { error } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        options: {
          shouldCreateUser: true,
          // This ensures we get OTP email, not magic link
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

  const handleVerifyOtp = async (e: React.FormEvent) => {
    e.preventDefault();
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

      // Store verified user data and move to display name input
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
      // Don't reset to EMAIL_INPUT, let user try again with same email
      setOtp('');
    } finally {
      setIsLoading(false);
    }
  };

  const handleCompleteLogin = async (e: React.FormEvent) => {
    e.preventDefault();
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

      // Fetch user profile from users table
      const { data: userProfiles, error: profileError } = await supabase
        .from('users')
        .select('id, display_name, email, is_permanently_banned, banned_until, health_tokens, gender')
        .eq('id', supabaseUser.id);

      if (profileError) {
        console.error('Profile fetch error:', profileError);
      }

      let userProfile = userProfiles && userProfiles.length > 0 ? userProfiles[0] : null;

      if (userProfile) {
        // Check ban status
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

        // Update session and fingerprint
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
        // No user profile exists - create one
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
          // Retry fetch in case of race condition
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

  const renderFormContent = () => {
    switch (step) {
      case 'EMAIL_INPUT':
        return (
          <form onSubmit={handleSendOtp} className="space-y-4">
            <div className="space-y-2">
              <label htmlFor="email" className="text-sm font-medium text-foreground">
                Enter your email address
              </label>
              <Input
                id="email"
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                autoFocus
                disabled={isLoading}
              />
              <p className="text-xs text-muted-foreground">
                We'll send a 6-digit code to verify your identity.
              </p>
            </div>

            <Button
              type="submit"
              variant="hero"
              size="xl"
              className="w-full"
              disabled={isLoading}
            >
              {isLoading ? (
                <div className="flex items-center gap-2">
                  <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
                  Sending Code...
                </div>
              ) : (
                <>
                  <Mail className="h-5 w-5" />
                  Continue with Email
                </>
              )}
            </Button>
          </form>
        );

      case 'OTP_VERIFICATION':
        return (
          <form onSubmit={handleVerifyOtp} className="space-y-4">
            <div className="space-y-2">
              <label htmlFor="otp" className="text-sm font-medium text-foreground">
                Enter the 6-digit code
              </label>
              <Input
                id="otp"
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                placeholder="000000"
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
                maxLength={6}
                autoComplete="one-time-code"
                autoFocus
                disabled={isLoading}
                className="text-center text-3xl tracking-[0.5em] font-mono"
              />
              <p className="text-xs text-muted-foreground">
                Code sent to <strong>{email}</strong>. Expires in 60 seconds.
                <button 
                  type="button" 
                  onClick={() => {
                    setStep('EMAIL_INPUT');
                    setOtp('');
                  }}
                  className="ml-1 text-primary hover:underline font-medium"
                  disabled={isLoading}
                >
                  Change email
                </button>
              </p>
            </div>

            <div className="space-y-2">
              <Button
                type="submit"
                variant="hero"
                size="xl"
                className="w-full"
                disabled={isLoading || otp.length !== 6}
              >
                {isLoading ? (
                  <div className="flex items-center gap-2">
                    <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
                    Verifying...
                  </div>
                ) : (
                  <>
                    <Key className="h-5 w-5" />
                    Verify Code
                  </>
                )}
              </Button>
              
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="w-full text-xs"
                onClick={handleSendOtp}
                disabled={isLoading}
              >
                Didn't receive code? Resend
              </Button>
            </div>
          </form>
        );

      case 'DISPLAY_NAME_INPUT':
        return (
          <form onSubmit={handleCompleteLogin} className="space-y-4">
            <div className="space-y-2">
              <label htmlFor="displayName" className="text-sm font-medium text-foreground">
                Choose your display name
              </label>
              <Input
                id="displayName"
                type="text"
                placeholder="Enter your name"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                maxLength={30}
                autoFocus
                disabled={isLoading}
              />
              <p className="text-xs text-muted-foreground">
                This is how others will see you in chat rooms. You can change it anytime.
              </p>
            </div>

            <Button
              type="submit"
              variant="hero"
              size="xl"
              className="w-full"
              disabled={isLoading}
            >
              {isLoading ? (
                <div className="flex items-center gap-2">
                  <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
                  Completing...
                </div>
              ) : (
                <>
                  <Users className="h-5 w-5" />
                  Start Chatting
                </>
              )}
            </Button>
          </form>
        );
        
      default:
        return null;
    }
  };

  const features = [
    { icon: Video, title: 'Video Chat', description: 'Crystal clear video calls' },
    { icon: Users, title: 'Meet People', description: 'Connect globally by interests' },
    { icon: Shield, title: 'Moderated', description: 'Safe & healthy community' },
  ];

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-4 relative overflow-hidden">
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 -left-32 w-64 h-64 bg-primary/10 rounded-full blur-[100px]" />
        <div className="absolute bottom-1/4 -right-32 w-96 h-96 bg-accent/10 rounded-full blur-[120px]" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-primary/5 rounded-full blur-[150px]" />
      </div>

      <div className="w-full max-w-md space-y-8 relative z-10 animate-slide-up">
        <div className="text-center space-y-4">
          <Logo size="xl" className="justify-center" />
          <p className="text-muted-foreground text-lg">
            Anonymous video chat, reimagined.
          </p>
        </div>

        <div className="glass-strong rounded-2xl p-8 space-y-6 shadow-2xl">
          {renderFormContent()}
        </div>

        <div className="grid grid-cols-3 gap-4">
          {features.map((feature) => (
            <div
              key={feature.title}
              className="glass rounded-xl p-4 text-center space-y-2 hover:border-primary/30 transition-colors"
            >
              <feature.icon className="h-6 w-6 mx-auto text-primary" />
              <h3 className="font-semibold text-sm">{feature.title}</h3>
              <p className="text-xs text-muted-foreground">{feature.description}</p>
            </div>
          ))}
        </div>

        <p className="text-center text-xs text-muted-foreground">
          By continuing, you agree to maintain a healthy community. 
          <br />Violations may result in account suspension.
        </p>
      </div>
    </div>
  );
}