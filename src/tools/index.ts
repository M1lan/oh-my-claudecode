/**
 * Tool Registry and MCP Server Creation
 *
 * This module exports all custom tools and provides helpers
 * for creating MCP servers with the Claude Agent SDK.
 */

import { z } from 'zod';
import { lspTools } from './lsp-tools.js';
import { astTools } from './ast-tools.js';
import { pythonReplTool } from './python-repl/index.js';

export { lspTools } from './lsp-tools.js';
export { astTools } from './ast-tools.js';
export { pythonReplTool } from './python-repl/index.js';

/**
 * Generic tool definition type
 */
export interface GenericToolDefinition {
  name: string;
  description: string;
  schema: z.ZodRawShape;
  handler: (
    args: unknown,
  ) => Promise<{ content: Array<{ type: 'text'; text: string }> }>;
}

/**
 * All custom tools available in the system
 */
export const allCustomTools: GenericToolDefinition[] = [
  ...(lspTools as unknown as GenericToolDefinition[]),
  ...(astTools as unknown as GenericToolDefinition[]),
  pythonReplTool as unknown as GenericToolDefinition,
];

/**
 * Get tools by category
 */
export function getToolsByCategory(
  category: 'lsp' | 'ast' | 'all',
): GenericToolDefinition[] {
  switch (category) {
    case 'lsp':
      return lspTools as unknown as GenericToolDefinition[];
    case 'ast':
      return astTools as unknown as GenericToolDefinition[];
    case 'all':
      return allCustomTools;
  }
}

/**
 * Create a Zod schema object from a tool's schema definition
 */
export function createZodSchema<T extends z.ZodRawShape>(
  schema: T,
): z.ZodObject<T> {
  return z.object(schema);
}

/**
 * Format for creating tools compatible with Claude Agent SDK
 */
export interface SdkToolFormat {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
  };
}

type ZodTypeForSchema = z.ZodType & {
  def: {
    defaultValue?: unknown;
    format?: unknown;
    type?: string;
  };
  description?: string;
  isInt?: boolean;
  isOptional(): boolean;
  unwrap(): z.ZodType;
  element?: z.ZodType;
};

/**
 * Convert our tool definitions to SDK format
 */
export function toSdkToolFormat(tool: GenericToolDefinition): SdkToolFormat {
  const zodSchema = z.object(tool.schema);
  const jsonSchema = zodToJsonSchema(zodSchema);

  return {
    name: tool.name,
    description: tool.description,
    inputSchema: jsonSchema,
  };
}

/**
 * Simple Zod to JSON Schema converter for tool definitions
 */
function zodToJsonSchema(schema: z.ZodObject<z.ZodRawShape>): {
  type: 'object';
  properties: Record<string, unknown>;
  required: string[];
} {
  const shape = schema.shape;
  const properties: Record<string, unknown> = {};
  const required: string[] = [];

  for (const [key, value] of Object.entries(shape)) {
    const zodType = value as unknown as ZodTypeForSchema;
    properties[key] = zodTypeToJsonSchema(zodType);

    if (!zodType.isOptional()) {
      required.push(key);
    }
  }

  return { type: 'object', properties, required };
}

/**
 * Convert individual Zod types to JSON Schema
 */
function zodTypeToJsonSchema(
  zodType: ZodTypeForSchema,
): Record<string, unknown> {
  const result: Record<string, unknown> = {};

  if (!zodType?.def) {
    return { type: 'string' };
  }

  if (zodType instanceof z.ZodOptional) {
    return zodTypeToJsonSchema(zodType.unwrap() as unknown as ZodTypeForSchema);
  }

  if (zodType instanceof z.ZodDefault) {
    const inner = zodTypeToJsonSchema(
      zodType.unwrap() as unknown as ZodTypeForSchema,
    );
    inner.default = zodType.def.defaultValue;
    return inner;
  }

  if (zodType.description) {
    result.description = zodType.description;
  }

  if (zodType instanceof z.ZodString) {
    result.type = 'string';
  } else if (zodType instanceof z.ZodNumber) {
    result.type = zodType.isInt ? 'integer' : 'number';
  } else if (zodType instanceof z.ZodBoolean) {
    result.type = 'boolean';
  } else if (zodType instanceof z.ZodArray) {
    result.type = 'array';
    result.items = zodType.element
      ? zodTypeToJsonSchema(zodType.element as unknown as ZodTypeForSchema)
      : { type: 'string' };
  } else if (zodType instanceof z.ZodEnum) {
    result.type = 'string';
    result.enum = zodType.options;
  } else if (zodType instanceof z.ZodObject) {
    return zodToJsonSchema(zodType);
  } else {
    result.type = 'string';
  }

  return result;
}
