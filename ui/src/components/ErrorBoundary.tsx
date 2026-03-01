import React from 'react';

interface State {
  error: Error | null;
}

export default class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  State
> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('UI crash:', error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center',
          justifyContent: 'center', height: '100vh', padding: 32,
          fontFamily: 'system-ui, sans-serif', textAlign: 'center',
          color: '#e8e0d4', background: '#1a1a1a',
        }}>
          <h2 style={{ marginBottom: 16 }}>Something went wrong</h2>
          <p style={{ opacity: 0.7, marginBottom: 24, maxWidth: 400 }}>
            {this.state.error.message}
          </p>
          <button
            onClick={() => window.location.reload()}
            style={{
              padding: '12px 24px', borderRadius: 8, border: 'none',
              background: '#c9785c', color: '#fff', fontSize: 16,
              cursor: 'pointer',
            }}
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
