import { useTheme } from "next-themes";
import { BsFillMoonFill, BsFillSunFill } from "react-icons/bs";

const ThemeChanger = () => {
  const { theme, setTheme } = useTheme();

  const toggleTheme = () => {
    setTheme(theme === "dark" ? "light" : "dark");
  };

  return (
    <div className="bg-white dark:bg-black px-4 flex items-center">
      <button onClick={toggleTheme}>
        {theme === "dark" ? (
          <BsFillSunFill size={24} color="white" />
        ) : (
          <BsFillMoonFill size={24} color="black" />
        )}
      </button>
    </div>
  );
};

export default ThemeChanger;
