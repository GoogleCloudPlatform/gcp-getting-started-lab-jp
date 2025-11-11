const colors: readonly string[] = [
  "slate",
  "red",
  "orange",
  "amber",
  "yellow",
  "lime",
  "green",
  "emerald",
  "teal",
  "cyan",
  "sky",
  "blue",
  "indigo",
  "violet",
  "purple",
  "fuchsia",
  "pink",
  "rose",
];

const intensities: readonly string[] = ["300", "500", "700"];

export const getRandomColor = (): string => {
  return (
    colors[Math.floor(Math.random() * colors.length)] +
    "-" +
    intensities[Math.floor(Math.random() * intensities.length)]
  );
};
