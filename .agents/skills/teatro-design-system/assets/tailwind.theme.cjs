/**
 * Teatro de la Ciudad de Coatzacoalcos — Preset de Tailwind CSS ("El Foro Monumental")
 * Uso en repo productivo (Tailwind v3):
 *   presets: [require('./tailwind.theme.cjs')]
 * O mezcla theme.extend dentro de tailwind.config.js / tailwind.config.ts.
 */
module.exports = {
  theme: {
    extend: {
      fontFamily: {
        display: ['Cinzel', 'Georgia', 'serif'],
        sans: ['Manrope', 'system-ui', 'sans-serif'],
      },
      colors: {
        primary: '#1E3A8A',            // Azul Golfo
        'golfo-deep': '#162C6B',       // Golfo Profundo (Admin tablas y acentos estructurales)
        secondary: '#D9CBB8',          // Arena Arquitectónica
        'arena-canvas': '#F6F4EF',     // Lienzo Arena Cálida (Consola Admin)
        'arena-subbar': '#EFECE4',     // Sub-barra Arena y thead Admin
        'arena-border': '#E4DED3',     // Borde y divisor Arena
        accent: '#E58E26',             // Dorado Atardecer
        'accent-text': '#B45309',      // Ámbar Accesible (texto sobre claro/Arena)
        highlight: '#38BDF8',          // Celeste Brisa
        'base-bg': '#F8F9FA',          // Blanco Nube (Portal Público)
        'base-text': '#0F172A',        // Carbón Pizarra
        'nocturno-bg': '#0B1736',      // Azul Nocturno del Golfo (Puerta QR)
        'nocturno-surface': '#13244E', // Tarjetas elevadas Puerta QR
      },
      borderRadius: {
        sm: '6px',
        md: '12px',
        lg: '16px',
        xl: '24px',
      },
    },
  },
};
