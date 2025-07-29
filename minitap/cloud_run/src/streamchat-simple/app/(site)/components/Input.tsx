"use client";

import clsx from "clsx";
import { ChangeEvent } from "react";

type InputProps = {
  label: string;
  id: string;
  type?: string;
  value: string | number;
  required?: boolean;
  disabled?: boolean;
  minLength?: number;
  maxLength?: number;
  onChange: (e: ChangeEvent<HTMLInputElement>) => void;
};

const Input: React.FC<InputProps> = ({
  label,
  id,
  required,
  type = "text",
  disabled,
  value,
  minLength,
  maxLength,
  onChange,
}) => {
  return (
    <div>
      <label
        htmlFor={id}
        className="
          block 
          text-sm 
          font-medium 
          leading-6 
          text-gray-900
        "
      >
        {label}
      </label>
      <div className="mt-2">
        <input
          id={id}
          type={type}
          required={required}
          autoComplete={id}
          value={value}
          disabled={disabled}
          onChange={onChange}
          minLength={minLength}
          maxLength={maxLength}
          className={clsx(
            `
            form-input
            block 
            w-full 
            rounded-md 
            border-0 
            py-1.5 
            text-gray-900 
            shadow-sm 
            ring-1 
            px-2
            ring-inset 
            ring-gray-300 
            placeholder:text-gray-400 
            focus:ring-2 
            focus:ring-inset 
            focus:ring-sky-600 
            sm:text-sm 
            sm:leading-6`,
            disabled && "opacity-50 cursor-default"
          )}
        />
      </div>
    </div>
  );
};

export default Input;
