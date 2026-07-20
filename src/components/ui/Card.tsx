import { type ReactNode, type HTMLAttributes } from "react";

interface CardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
  hover?: boolean;
  as?: "div" | "section" | "article";
}

export function Card({
  children,
  hover = false,
  className = "",
  ...rest
}: CardProps) {
  return (
    <div
      className={`aether-card ${hover ? "aether-card-hover" : ""} ${className}`}
      {...rest}
    >
      {children}
    </div>
  );
}
