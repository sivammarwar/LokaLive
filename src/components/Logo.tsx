import { cn } from '@/lib/utils';

interface LogoProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  className?: string;
}

export function Logo({ size = 'md', className }: LogoProps) {
  const sizeClasses = {
    sm: 'text-2xl',
    md: 'text-4xl',
    lg: 'text-6xl',
    xl: 'text-8xl',
  };

  return (
    <div className={cn('flex items-center gap-2', className)}>
      <div className="relative">
        <span
          className={cn(
            sizeClasses[size],
            'font-extrabold tracking-tight text-gradient-primary'
          )}
        >
          Loka
        </span>
        <div className="absolute -inset-4 bg-primary/20 blur-2xl rounded-full -z-10" />
      </div>
    </div>
  );
}
