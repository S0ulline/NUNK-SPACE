import React from 'react';

export default function Root({ children }: { children: React.ReactNode }) {
    return (
        <>
            {/* Наши анимированные сферы для фона */}
            <div className="background-fx">
                <div className="orb orb-1"></div>
                <div className="orb orb-2"></div>
                <div className="orb orb-3"></div>
            </div>

            {/* Сам контент документации Docusaurus */}
            {children}
        </>
    );
}