module.exports = {
  content: [
    './apps/landing/public/index.html',
    './apps/landing/public/sistemas.html',
    './apps/landing/public/soluciones.html',
    './apps/landing/public/nosotros.html',
    './apps/landing/public/assets/landing.js',
  ],
  plugins: [require('@tailwindcss/forms'), require('@tailwindcss/container-queries')],
      darkMode: "class",
      theme: {
        extend: {
          "colors": {
            "inverse-primary": "#c6c6c9",
            "on-surface-variant": "#44474a",
            "on-primary": "#ffffff",
            "primary-container": "#1e2022",
            "on-surface": "#1b1c1a",
            "tertiary-container": "#002042",
            "on-primary-container": "#86878a",
            "on-tertiary-fixed-variant": "#0a4783",
            "on-secondary": "#ffffff",
            "on-error-container": "#93000a",
            "secondary-fixed-dim": "#ffb68c",
            "primary-fixed-dim": "#c6c6c9",
            "primary": "#06080a",
            "surface-container-highest": "#e4e2df",
            "tertiary-fixed-dim": "#a6c8ff",
            "surface-dim": "#dbdad7",
            "outline": "#75777a",
            "on-error": "#ffffff",
            "error-container": "#ffdad6",
            "on-secondary-fixed": "#321200",
            "secondary": "#994703",
            "secondary-container": "#fc934f",
            "on-secondary-fixed-variant": "#753400",
            "on-secondary-container": "#6d3000",
            "primary-fixed": "#e2e2e5",
            "on-tertiary-fixed": "#001c3a",
            "surface-variant": "#e4e2df",
            "error": "#ba1a1a",
            "surface-container": "#efeeeb",
            "secondary-fixed": "#ffdbc9",
            "on-tertiary-container": "#5b89c9",
            "on-background": "#1b1c1a",
            "on-tertiary": "#ffffff",
            "background": "#fbf9f6",
            "inverse-surface": "#30312f",
            "surface-tint": "#5d5e61",
            "on-primary-fixed": "#1a1c1e",
            "surface-container-lowest": "#ffffff",
            "outline-variant": "#c5c6ca",
            "surface-bright": "#fbf9f6",
            "tertiary-fixed": "#d4e3ff",
            "surface-container-low": "#f5f3f0",
            "tertiary": "#000818",
            "surface": "#fbf9f6",
            "inverse-on-surface": "#f2f0ed",
            "surface-container-high": "#eae8e5",
            "on-primary-fixed-variant": "#454749"
          },
          "borderRadius": {
            "DEFAULT": "0.25rem",
            "lg": "0.5rem",
            "xl": "0.75rem",
            "full": "9999px"
          },
          "spacing": {
            "space-xs": "0.25rem",
            "space-md": "0.875rem",
            "space-xl": "2.25rem",
            "space-lg": "1.5rem",
            "gutter-desktop": "1.5rem",
            "margin": "1.25rem",
            "gutter": "1.25rem",
            "margin-desktop": "3rem",
            "space-sm": "0.5rem"
          },
          "fontFamily": {
            "display-hero-mobile": [
              "Plus Jakarta Sans"
            ],
            "headline-lg-mobile": [
              "Plus Jakarta Sans"
            ],
            "label-caps": [
              "Plus Jakarta Sans"
            ],
            "headline-sm": [
              "Plus Jakarta Sans"
            ],
            "headline-lg": [
              "Plus Jakarta Sans"
            ],
            "label-mono-xs": [
              "JetBrains Mono"
            ],
            "body-md": [
              "Plus Jakarta Sans"
            ],
            "display-hero": [
              "Plus Jakarta Sans"
            ],
            "body-lg": [
              "Plus Jakarta Sans"
            ],
            "headline-md": [
              "Plus Jakarta Sans"
            ],
            "label-mono": [
              "JetBrains Mono"
            ],
            "body-sm": [
              "Plus Jakarta Sans"
            ]
          },
          "fontSize": {
            "display-hero-mobile": [
              "36px",
              {
                "lineHeight": "44px",
                "letterSpacing": "-0.025em",
                "fontWeight": "700"
              }
            ],
            "headline-lg-mobile": [
              "26px",
              {
                "lineHeight": "34px",
                "letterSpacing": "-0.015em",
                "fontWeight": "600"
              }
            ],
            "label-caps": [
              "11px",
              {
                "lineHeight": "16px",
                "letterSpacing": "0.06em",
                "fontWeight": "700"
              }
            ],
            "headline-sm": [
              "18px",
              {
                "lineHeight": "26px",
                "letterSpacing": "-0.01em",
                "fontWeight": "600"
              }
            ],
            "headline-lg": [
              "32px",
              {
                "lineHeight": "40px",
                "letterSpacing": "-0.02em",
                "fontWeight": "600"
              }
            ],
            "label-mono-xs": [
              "10px",
              {
                "lineHeight": "14px",
                "letterSpacing": "0.04em",
                "fontWeight": "500"
              }
            ],
            "body-md": [
              "15px",
              {
                "lineHeight": "24px",
                "letterSpacing": "0em",
                "fontWeight": "400"
              }
            ],
            "display-hero": [
              "56px",
              {
                "lineHeight": "64px",
                "letterSpacing": "-0.03em",
                "fontWeight": "700"
              }
            ],
            "body-lg": [
              "17px",
              {
                "lineHeight": "26px",
                "letterSpacing": "-0.005em",
                "fontWeight": "400"
              }
            ],
            "headline-md": [
              "22px",
              {
                "lineHeight": "30px",
                "letterSpacing": "-0.015em",
                "fontWeight": "600"
              }
            ],
            "label-mono": [
              "12px",
              {
                "lineHeight": "16px",
                "letterSpacing": "0.02em",
                "fontWeight": "500"
              }
            ],
            "body-sm": [
              "13px",
              {
                "lineHeight": "20px",
                "letterSpacing": "0.005em",
                "fontWeight": "400"
              }
            ]
          }
        },
      },
    }
