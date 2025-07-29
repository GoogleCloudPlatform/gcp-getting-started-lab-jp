const animals: readonly string[] = [
  "chicken",
  "cat",
  "cow",
  "fox",
  "elephant",
  "giraffe",
  "deer",
  "dog",
  "goat",
  "gorilla",
  "panda",
  "koala",
  "buffalo",
  "monkey",
  "wolf",
  "rabbit",
  "pig",
  "mouse",
  "hippo",
  "rhino",
  "horse",
  "lion",
  "wildboar",
  "bear",
  "sheep",
];

export const getRandomAnimal = (): string => {
  return animals[Math.floor(Math.random() * animals.length)];
};
