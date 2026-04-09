import React from 'react';
import Admonition from '@theme-original/Admonition';
import HeartIcon from '@site/static/img/heart-admonition.svg';

export default function AdmonitionWrapper(props) {
    // Если это наш кастомный блок
    if (props.type === 'gratitude') {
        return (
            <Admonition
                icon={<HeartIcon />} /* Можно использовать emoji или вставить <svg> */
                title="Благодарность авторам" /* Дефолтный заголовок, если не указать другой */
                className="alert--gratitude"
                {...props}
            />
        );
    }

    // Для всех остальных блоков (tip, info, danger) возвращаем всё как было
    return <Admonition {...props} />;
}