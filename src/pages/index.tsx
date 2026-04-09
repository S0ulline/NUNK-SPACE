import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

// Блок с приветствием и кнопками (Hero)
function HomepageHeader() {
    const {siteConfig} = useDocusaurusContext();
    return (
        <header className="hero" style={{ minHeight: '60vh', display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
            <div className="container">
                {/* ЗАМЕНА ТЕКСТА НА ЛОГОТИП */}
                <img
                    src="/img/large-logo.png"
                    alt={siteConfig.title || 'NUNK SPACE Logo'}
                    style={{
                        maxWidth: '90%',   // Не дает логотипу вылезать за пределы экрана
                        height: 'auto',       // Сохраняет пропорции
                        maxHeight: '100px',   // Ограничивает максимальную высоту, чтобы лого не было гигантским
                        display: 'block',     // Помогает с центрированием
                        margin: '0 auto 30px' // Центрирует по горизонтали и добавляет отступ снизу
                    }}
                />

                <p className="hero__subtitle" style={{ fontSize: '1.3rem', color: '#d1d5db', maxWidth: '800px', margin: '0 auto 40px' }}>
                    Твоя персональная база знаний по современным сетевым технологиям, сложной маршрутизации и криптографической защите трафика.
                </p>
                <div style={{ display: 'flex', gap: '20px', justifyContent: 'center', flexWrap: 'wrap' }}>
                    <Link
                        className="button button--primary button--lg"
                        to="/docs/">
                        Начать изучение 🚀
                    </Link>
                    <Link
                        className="button button--secondary button--lg"
                        to="/docs/glossary">
                        Словарь терминов 📚
                    </Link>
                </div>
            </div>
        </header>
    );
}

// Карточки с основными разделами
const FeatureList = [
    {
        title: 'Свой VPN',
        icon: '🛡️',
        description: (
            <>
                Пошаговые руководства по аренде VPS и развертыванию мощных панелей управления (3x-ui, S-UI) с поддержкой Xray и Sing-box.
            </>
        ),
        link: '/docs/self-vpn',
    },
    {
        title: 'Прокси для Telegram',
        icon: '✈️',
        description: (
            <>
                Настройка сверхбыстрых приватных узлов связи (MTProto, SOCKS5) с маскировкой трафика под Fake TLS для бесперебойной работы мессенджера.
            </>
        ),
        link: '/docs/proxy/telegram-proxy',
    },
    {
        title: 'Сетевая безопасность',
        icon: '🔐',
        description: (
            <>
                Глубокий разбор протоколов Hysteria 2, VLESS, методов обфускации Reality и защиты от систем глубокого анализа трафика (DPI).
            </>
        ),
        link: '/docs/', // Замени на нужную ссылку, если есть отдельный раздел
    },
];

function Feature({icon, title, description, link}) {
    return (
        <div className={clsx('col col--4')} style={{ padding: '15px' }}>
            <Link to={link} style={{ textDecoration: 'none', color: 'inherit', display: 'block', height: '100%' }}>
                <div className="card" style={{ height: '100%', padding: '30px', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                    <div style={{ fontSize: '3rem', marginBottom: '20px' }}>{icon}</div>
                    <h3 style={{ fontSize: '1.5rem', color: '#fff', marginBottom: '15px' }}>{title}</h3>
                    <p style={{ color: '#a8a29e', lineHeight: 1.6, flexGrow: 1 }}>{description}</p>
                </div>
            </Link>
        </div>
    );
}

function HomepageFeatures() {
    return (
        <section style={{ padding: '4rem 0' }}>
            <div className="container">
                <div className="row">
                    {FeatureList.map((props, idx) => (
                        <Feature key={idx} {...props} />
                    ))}
                </div>
            </div>
        </section>
    );
}

// Главный компонент страницы
export default function Home() {
    return (
        <Layout
            title="Главная"
            description="База знаний по сетевым технологиям и VPN">
            <HomepageHeader />
            <main>
                <HomepageFeatures />
            </main>
        </Layout>
    );
}