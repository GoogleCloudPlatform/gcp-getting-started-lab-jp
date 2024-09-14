export const logError = (obj: Object) => {
  console.log(JSON.stringify({ ...obj, severity: "ERROR" }));
};

export const logDebug = (obj: Object) => {
  console.log(JSON.stringify({ ...obj, severity: "DEBUG" }));
};

export const logInfo = (obj: Object) => {
  console.log(JSON.stringify({ ...obj, severity: "INFO" }));
};

export const logWarn = (obj: Object) => {
  console.log(JSON.stringify({ ...obj, severity: "WARN" }));
};
