export const markdownComponents={
  ul: ({ node, ...props }) => (
    <ul className="list-disc pl-5" {...props} />
  ),
  table: ({ node, ...props }) => (
    <table className="table-auto w-full border-collapse border border-gray-300" {...props} />
  ),
  thead: ({ node, ...props }) => (
    <thead className="bg-gray-200" {...props} />
  ),
  th: ({ node, ...props }) => (
    <th className="border border-gray-300 px-4 py-2 text-left" {...props} />
  ),
  td: ({ node, ...props }) => (
    <td className="border border-gray-300 px-4 py-2" {...props} />
  ),
  h1: ({ node, ...props }) => (
    <h1 className="text-3xl font-bold my-4" {...props} />
  ),
  h2: ({ node, ...props }) => (
    <h2 className="text-2xl font-bold my-3" {...props} />
  ),
  h3: ({ node, ...props }) => (
    <h3 className="text-xl font-bold my-2" {...props} />
  ),
  h4: ({ node, ...props }) => (
    <h4 className="text-lg font-semibold my-1" {...props} />
  ),
  h5: ({ node, ...props }) => (
    <h5 className="text-base font-semibold" {...props} />
  ),
  h6: ({ node, ...props }) => (
    <h6 className="text-sm font-semibold" {...props} />
  ),
};
