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

export const getAvatarColor = (owner: string): string => {
  return (
    colors[owner.charCodeAt(0) % colors.length] +
    "-" +
    intensities[owner.charCodeAt(1) % intensities.length]
  );
};
